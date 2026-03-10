# CUJ: Runaway Process Auto-Throttle

**Last updated:** 2026-03-06
**Actor:** Mac user (developer or power user)
**Trigger:** A background process starts consuming excessive CPU

---

## Journey

### 1. Setup (one-time)
- User installs Lowbeer (DMG or Homebrew)
- Lowbeer appears in the menu bar
- Default settings work out of the box (80% threshold, 30s sustained, Stop action)
- No configuration required

### 2. Detection
- A background process (e.g., runaway `node`, `zsh`, Chrome helper) starts burning >80% CPU
- Lowbeer's ProcessMonitor detects it within 3 seconds (one poll interval)
- The sustained timer begins counting

### 3. Throttle Decision
- After 30 seconds of sustained high CPU, RuleEvaluator checks:
  - Is the process on the safety list? → Skip
  - Is there a per-app rule? → Use rule's threshold/action
  - Is the process in the foreground? → Skip (auto-resume)
  - Is there an active time schedule? → Check if within window
- Decision: throttle

### 4. Throttle Action
- ThrottleEngine sends SIGSTOP to the process
- ThrottleSession records the state
- NotificationManager sends a macOS notification: "Lowbeer throttled [process name]"
- Menu bar popover shows the process as throttled with its CPU history sparkline

### 5. User Interaction (optional)
- User clicks the menu bar icon → sees popover with throttled process highlighted
- User can manually resume the process from the popover
- Or: user switches to the throttled app → ForegroundObserver auto-resumes it
- Or: user does nothing → process stays throttled

### 6. Cleanup
- When user quits Lowbeer, AppDelegate resumes all throttled processes
- No processes are left in SIGSTOP state after quit

---

## Success Criteria
- Process detected within one poll interval (3s)
- Throttle applied after sustained duration (30s default)
- Notification delivered to user
- No system instability from throttling
- Clean resume on app quit or foreground switch

## Failure Modes
| Failure | Mitigation |
|---------|-----------|
| PID reuse — wrong process throttled | Name verification before SIGSTOP; start-time check (planned) |
| System process throttled | Safety list (hardcoded, non-overridable) |
| Throttled app brought to foreground stays frozen | ForegroundObserver auto-resume |
| Lowbeer crashes during active throttle | AppDelegate cleanup; OS resumes on process exit |
