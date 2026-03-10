# CPU Monitoring

## How It Works

1. `ProcessSampler.sampleAll()` calls `proc_listallpids` to enumerate all PIDs
2. For each PID, `proc_pidinfo(pid, PROC_PIDTASKINFO)` returns cumulative CPU nanoseconds (`pti_total_user` + `pti_total_system`)
3. `ProcessMonitor` stores previous samples and computes delta:
   ```
   cpuPercent = (deltaNanoseconds / deltaWallclockSeconds / 1e9) * 100
   ```
4. This gives Activity Monitor-style per-core percentages (one full core = ~100%)
5. Processes with <0.1% CPU are filtered; top 50 by CPU are kept

## Key Files

| File | Role |
|------|------|
| `Core/ProcessSnapshot.swift` | `ProcessSampler.sampleAll()` — raw libproc calls, returns `[pid_t: ProcessSnapshot]` |
| `Core/ProcessMonitor.swift` | Timer-driven poller, delta calculation, publishes `@Observable` process list |
| `Models/ProcessInfo.swift` | Per-process observable model (pid, name, cpuPercent, history, throttle state) |
| `Models/ProcessHistory.swift` | Fixed-size ring buffer (60 samples × 3s = ~3 min history) |

## Gotchas

**libproc bridging:** `PROC_PIDPATHINFO_MAXSIZE` isn't bridged to Swift. Hardcoded as `PROC_PIDPATHINFO_SIZE = 4096` in `ProcessSnapshot.swift`.

**Name collision:** Our `ProcessInfo` model shadows Foundation's `ProcessInfo`. Always use `Foundation.ProcessInfo` when you need the system one (e.g., `Foundation.ProcessInfo.processInfo.processIdentifier`). The helper `ProcessInfo_Helpers` exists for this reason.

**Icon lookup:** `ProcessIcon.swift` walks up from a binary path to find its `.app` bundle, then uses `NSWorkspace.shared.icon(forFile:)`. Results are cached by bundle ID or path.

## Poll Cycle

```
Timer fires (default 3s)
  → ProcessSampler.sampleAll()          [background queue]
    → proc_listallpids → all PIDs
    → proc_pidinfo per PID → cumulative CPU ns
  → Compare with previous sample
    → delta ns / delta wallclock = CPU %
  → Merge with NSRunningApplication data (icons, bundle IDs, localized names)
  → Sort by CPU desc, keep top 50
  → Publish to @Observable processes     [main queue]
```
