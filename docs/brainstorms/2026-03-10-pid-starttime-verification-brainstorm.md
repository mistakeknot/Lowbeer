---
artifact_type: brainstorm
bead: Lowbeer-hht
stage: discover
---

# PID Start-Time Verification for Reuse Safety

## What We're Building

Harden Lowbeer's process identity model by tracking `(pid, startTime)` tuples instead of just `pid`. macOS reuses PIDs fast — sometimes within milliseconds under heavy fork() load (build tools, npm scripts, shell pipelines). The current name-based `verifyProcess()` check fails when two processes share the same name (e.g., two `node` instances).

This prevents three failure modes:
1. **Same-name processes** — two `node`/`python`/`cargo` instances where PID reuse goes undetected
2. **Critical process hit** — a system process inherits a PID and gets frozen
3. **Duty-cycle thrashing** — during the 1-second duty cycle, PID reuse mid-cycle sends SIGSTOP/SIGCONT to the wrong process

## Why This Approach

**API: `sysctl(KERN_PROC, KERN_PROC_PID)`** returns `kinfo_proc` with `p_starttime` as a `struct timeval` (seconds + microseconds). This is the canonical process start time used by Activity Monitor and `launchd`. No entitlements required, works for any same-user process.

We chose this over `proc_pidinfo(PROC_PIDTASKINFO)` which has `pti_start_time` — that's the Mach task creation time, which can differ from process start time after `exec()`.

**Storage: ProcessSnapshot → ProcessInfo → ThrottleSession.** Capture start time during `ProcessSampler.sampleAll()`, flow it through the existing `ProcessInfo` model, and store it in `ThrottleSession` at creation. Every signal dispatch checks the `(pid, startTime)` tuple.

## Key Decisions

1. **API choice: sysctl KERN_PROC** — canonical source, no entitlements, matches Activity Monitor behavior
2. **Storage path: ProcessSnapshot + ProcessInfo** — start time flows through the existing data pipeline rather than being captured separately
3. **Failure mode: fail closed** — if sysctl can't verify a PID (process exited), deactivate the throttle session immediately. We'd rather miss throttling than freeze the wrong process.
4. **Verification replaces name check** — `verifyProcess()` checks `(pid, startTime)` match. Name check becomes redundant but can remain as defense-in-depth.

## Open Questions

- **struct timeval comparison precision** — should we compare seconds only, or include microseconds? Microseconds are more precise but could theoretically differ due to clock adjustments. Likely fine to compare both fields.
- **ProcessMonitor cache invalidation** — when `processCache[pid]` has a stale start time (PID was reused), the cache entry should be evicted. Need to check start time during cache lookup, not just name.
- **Testing strategy** — hard to trigger real PID reuse deterministically. May need mock-based tests for `verifyProcess()` plus a stress test that forks rapidly.
