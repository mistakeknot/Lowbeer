# Safety Model

Lowbeer sends SIGSTOP to processes, which can freeze critical system services if applied carelessly. Multiple layers prevent this.

## Hardcoded Protected Processes

`SafetyList.protectedNames` (in `Helpers/SafetyList.swift`):

```
kernel_task, launchd, WindowServer, loginwindow, Finder, Dock,
SystemUIServer, coreaudiod, audiod, coreduetd, powerd,
diskarbitrationd, notifyd, opendirectoryd, securityd, trustd,
configd, mds, mds_stores, distnoted, UserEventAgent, Lowbeer
```

## Protected Path Prefixes

Anything under these paths is never throttled:
- `/System/`
- `/usr/libexec/`
- `/usr/sbin/`

## Self-Protection

- Lowbeer's own PID is always excluded (`Foundation.ProcessInfo.processInfo.processIdentifier`)
- PIDs 0 and 1 (kernel, launchd) are always excluded

## User Allowlist

Users can add processes via Settings → Allowlist. Stored in `~/Library/Application Support/Lowbeer/lowbeer_allowlist.json`. Matches by display name, bundle ID, or executable path.

## PID Verification

macOS reuses PIDs. Before every SIGSTOP, `ThrottleSession.verifyProcess()`:
1. Calls `proc_name(pid)` to get the current process name for that PID
2. Compares against the stored `processName` from when the session was created
3. If mismatch → session is deactivated, no signal sent

## Quit Cleanup

On app termination, `ThrottleEngine.resumeAll()` sends SIGCONT to every stopped process. This prevents leaving zombie-stopped processes if Lowbeer crashes or the user quits.

## What Could Still Go Wrong

- **Force-kill of Lowbeer** (`kill -9`) skips cleanup — stopped processes stay stopped. User must manually `kill -CONT <pid>` or reboot.
- **Same-user only** — Lowbeer can only signal processes owned by the same user. Root-owned processes are immune (this is a feature, not a bug).
- **launchd-respawned daemons** — stopping a daemon that launchd monitors may cause launchd to restart it or report it as crashed. The safety list prevents this for known daemons.
