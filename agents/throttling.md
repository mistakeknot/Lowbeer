# Throttling

## Mechanisms

### Full Stop (SIGSTOP)
- `kill(pid, SIGSTOP)` — process uses 0% CPU, fully frozen
- `kill(pid, SIGCONT)` — process resumes normally
- Before sending SIGSTOP, `ThrottleSession.verifyProcess()` checks PID still maps to expected process name (PIDs get reused by macOS)

### Duty-Cycle Throttling
For partial limits (e.g., 25% CPU), uses a 1-second duty cycle:
- SIGCONT for `fraction × 1s` (e.g., 250ms for 25%)
- SIGSTOP for the remainder (e.g., 750ms)
- Repeats via `Timer.scheduledTimer`
- Minimum run fraction: 5%. Maximum: 95%.

## Key Files

| File | Role |
|------|------|
| `Core/ThrottleEngine.swift` | Subscribes to ProcessMonitor, evaluates rules, manages sessions |
| `Core/ThrottleSession.swift` | Per-process state machine (activate/deactivate, duty-cycle timer) |
| `Core/RuleEvaluator.swift` | Matches process → rule → action (static, no state) |
| `Core/ScheduleEvaluator.swift` | Time-of-day / day-of-week window matching |
| `Core/ForegroundObserver.swift` | NSWorkspace activation watcher for auto-resume |
| `Models/ThrottleRule.swift` | Rule model: identity, threshold, sustained duration, action, schedule |

## Rule Evaluation Order

`RuleEvaluator.evaluate()` runs this cascade:

1. **Safety list** — always skip (see [safety.md](safety.md))
2. **Per-app rule** — first matching enabled rule wins:
   - Check schedule (if set, must be active)
   - Check foreground (if `throttleInBackground`, skip foreground processes)
   - Check threshold + sustained duration
   - Return rule's action, or nil if threshold not met
   - **Does not fall through to global** — a matched rule claims the process
3. **Global threshold** — if no per-app rule matched, check `globalCPUThreshold` for `sustainedSeconds` consecutive samples

## Auto-Resume Triggers

- **Foreground:** `ForegroundObserver` detects `NSWorkspace.didActivateApplicationNotification` → immediately SIGCONT + remove session
- **Manual:** User clicks "Resume" in popover → `ThrottleEngine.resume(pid:)`
- **Global pause:** Pause button → `ThrottleEngine.resumeAll()` + `settings.isPaused = true`
- **Threshold drop:** Process CPU drops below threshold → session deactivated on next evaluation cycle

## ThrottleSession Lifecycle

```
ThrottleSession.init(pid, processName, rule, action)
  │
  ├─ .activate()
  │    ├─ .stop → verifyProcess() → kill(SIGSTOP)
  │    ├─ .throttleTo(frac) → verifyProcess() → start duty-cycle timer
  │    └─ .notifyOnly → no-op (handled externally)
  │
  └─ .deactivate()
       ├─ Invalidate duty-cycle timer
       └─ If stopped → kill(SIGCONT)
```

## ThrottleAction Variants

```swift
enum ThrottleAction {
    case stop                  // SIGSTOP, 0% CPU
    case throttleTo(Double)    // duty-cycle, e.g. 0.25 = 25% CPU
    case notifyOnly            // notification only, no signal
}
```
