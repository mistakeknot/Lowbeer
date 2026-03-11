---
artifact_type: prd
bead: Lowbeer-hht
stage: design
---
# PRD: PID Start-Time Verification

## Problem
macOS reuses PIDs rapidly. Lowbeer's current name-based `verifyProcess()` fails when two processes share the same name (e.g., two `node` instances), risking SIGSTOP/SIGCONT sent to the wrong process.

## Solution
Track `(pid, startTime)` tuples throughout the process pipeline. Use `sysctl(KERN_PROC, KERN_PROC_PID)` to capture `p_starttime` and verify it before every signal dispatch. Fail closed — if verification fails, deactivate the throttle session.

## Features

### F1: Capture Start Time in ProcessSnapshot
**What:** Add `startTime: timeval` to `ProcessSnapshot` by calling `sysctl(KERN_PROC, KERN_PROC_PID)` during `ProcessSampler.sampleAll()`.
**Acceptance criteria:**
- [ ] `ProcessSnapshot` has a `startTime: timeval` field
- [ ] `sampleAll()` populates `startTime` via sysctl for each PID
- [ ] If sysctl fails for a PID, that PID is skipped (no snapshot emitted)

### F2: Thread Start Time Through ProcessInfo and Cache
**What:** Add `startTime: timeval` to `ProcessInfo`. Update `ProcessMonitor.processCache` to evict entries when PID reuse is detected (same PID, different start time).
**Acceptance criteria:**
- [ ] `ProcessInfo` has a `startTime: timeval` field, set from `ProcessSnapshot`
- [ ] `ProcessMonitor.processCache` check compares `startTime`, not just `name`
- [ ] When a PID is reused (different start time), the old cache entry is replaced

### F3: Start-Time Verified Signal Dispatch
**What:** Rewrite `ThrottleSession.verifyProcess()` to check `(pid, startTime)` via sysctl. Fail closed — if sysctl returns no data or a different start time, deactivate immediately.
**Acceptance criteria:**
- [ ] `ThrottleSession` stores `startTime: timeval` captured at creation
- [ ] `verifyProcess()` calls sysctl and compares `startTime` (both `tv_sec` and `tv_usec`)
- [ ] If sysctl fails (process exited): returns false, session deactivates
- [ ] If start time differs (PID reused): returns false, session deactivates
- [ ] Name check retained as defense-in-depth (log warning if name differs but start time matches)
- [ ] Duty-cycle timer deactivates on verification failure (existing behavior preserved)

## Non-goals
- Privileged process verification (root-owned processes) — Phase 3
- Mach task_suspend integration — Phase 2
- Automated PID reuse stress testing — separate bead (Lowbeer-p5i)

## Dependencies
- None — `sysctl` and `kinfo_proc` are available in Darwin headers, already imported

## Open Questions
- `timeval` comparison: compare both `tv_sec` and `tv_usec` (recommended — maximum precision, no known issues with clock adjustment on macOS for process start times)
