# PRD: Smart Battery Drain Notification

**Date:** 2026-03-12
**Bead:** Lowbeer-1yd
**Priority:** P1
**Parent:** Lowbeer-waw (Battery detective epic)
**Depends on:** Lowbeer-eck (EnergyLedger) — DONE
**Blocks:** Lowbeer-q0a (Battery detective popover — can use DrainDetector's baseline)

---

## Problem

Lowbeer throttles runaway processes but the user only learns about battery drain if they actively check the menu bar. By the time they notice, they may have already lost significant battery life. There's no proactive alert for "your battery is dying faster than normal."

## Solution

Add a `DrainDetector` that compares current system power draw against a rolling baseline and fires a notification when drain exceeds 2x normal for 2+ minutes, but only when on battery power. The notification names the top culprit and offers a one-tap throttle action.

## Requirements

### Must Have

1. **Battery state detection** — Detect AC vs battery power via `IOPSCopyPowerSourcesInfo`. Suppress all drain alerts when on AC power.
2. **Power baseline** — Ring buffer of recent system watts readings (200 samples ≈ 10 min at 3s intervals). Computes rolling average for comparison.
3. **Drain detection logic** — Trigger when `currentWatts > baseline * 2.0` sustained for 40 consecutive poll cycles (~2 min). Require baseline to be warmed (≥100 samples).
4. **Notification with action** — Fire a notification with the top culprit's name, CPU%, and duration. Include "Throttle It" and "Dismiss" action buttons.
5. **Cooldown** — After firing, suppress for 10 minutes to avoid spam.
6. **Respect notificationsEnabled** — Honor the existing setting.

### Nice to Have (defer)

- Configurable multiplier threshold (hardcode 2.0 for v1)
- Settings UI for drain alert preferences
- Notification shows estimated battery time remaining

### Out of Scope

- Battery detective popover view (Lowbeer-q0a)
- Battery capacity/health monitoring
- Historical drain comparison
- Per-process drain notifications

## Design

### New Files

| File | Purpose |
|------|---------|
| `Lowbeer/Core/DrainDetector.swift` | DrainDetector class, PowerBaseline struct, battery state detection |

### Modified Files

| File | Change |
|------|--------|
| `Lowbeer/Core/ProcessMonitor.swift` | Call `drainDetector.evaluate()` at end of poll cycle |
| `Lowbeer/Core/NotificationManager.swift` | Add `notifyDrain()` method + new action category |
| `Lowbeer.xcodeproj/project.pbxproj` | Add new file, link IOKit framework |

### Data Flow

```
ProcessMonitor.poll()
  ├── PowerSampler.sample()           → system watts
  ├── EnergyLedger.record()           → per-app Wh (existing)
  └── DrainDetector.evaluate()        → drain alert check
       ├── PowerBaseline.append()     → update rolling average
       ├── BatteryState.isOnBattery() → suppress on AC
       └── if sustained high drain    → NotificationManager.notifyDrain()
```

### Threading

`DrainDetector.evaluate()` is called from the main-thread `DispatchQueue.main.async` block in `poll()`, same as EnergyLedger. All state is main-thread only.

## Success Criteria

1. Running `yes > /dev/null &` on battery power for 3+ minutes triggers a drain notification naming `yes` as the top culprit
2. Same test on AC power produces no notification
3. After dismissing, no re-notification for 10 minutes even if drain continues
4. Notification "Throttle It" action stops the culprit process
5. No notification during the first ~5 minutes after launch (baseline warming)
6. Build succeeds, all existing tests pass, no performance regression
