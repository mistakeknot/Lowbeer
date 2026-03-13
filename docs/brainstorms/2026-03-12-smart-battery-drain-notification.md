# Smart Battery Drain Notification — Brainstorm

**Date:** 2026-03-12
**Bead:** Lowbeer-1yd
**Parent:** Lowbeer-waw (Battery detective epic)
**Depends on:** Lowbeer-eck (EnergyLedger) — DONE

---

## The Goal

Fire a notification when the Mac is draining battery abnormally fast, telling the user *what* is causing it and giving them a one-tap fix. This is the proactive layer of Battery Detective — the user doesn't need to look at the menu bar to know something is wrong.

**From the bead description:**
> Fire a notification when battery drain is abnormal. Compare current system power draw against rolling 24h baseline. Trigger at 2x-3x normal draw sustained for 2+ minutes. Include top culprit process name, CPU%, and duration. Action buttons: Throttle It, Dismiss. Only fires on battery (not AC).

---

## What We Already Have

| Component | State | Relevance |
|-----------|-------|-----------|
| `EnergyLedger` | Just built | Per-app watts and cumulative Wh — identifies the top culprit |
| `PowerSampler` | Working | System-level watts via IOReport each poll cycle |
| `LowbeerNotificationManager` | Working | Delivers notifications with action buttons (Throttle/Ignore pattern) |
| `ProcessMonitor.poll()` | Working | 3s poll cycle, produces `latestPower` and `processes` |
| `LowbeerSettings.notificationsEnabled` | Working | User preference for notifications |

**What we don't have yet:**
1. **Battery vs AC detection** — IOPSCopyPowerSourcesInfo or similar
2. **System power history / baseline** — rolling average of recent system watts
3. **Drain alert logic** — sustained threshold comparison + cooldown to avoid spam

---

## Design

### Component: DrainDetector

A new class that runs alongside ProcessMonitor. Each poll cycle, it receives the current system watts and decides whether to fire a notification.

```
ProcessMonitor.poll()
  → power = PowerSampler.sample()
  → DrainDetector.evaluate(power, topProcess, totalCPU)
    → if on battery AND sustained high drain → fire notification
```

### Battery State Detection

Two approaches:

**Option A: IOPSCopyPowerSourcesInfo (IOKit public API)**
- Public, stable API. Returns battery state, current, voltage, capacity.
- Requires linking IOKit framework.
- Provides `isCharging`, `currentCapacity`, `maxCapacity`, `isACPowered`.
- Well-documented, used by every battery app.

**Option B: NSProcessInfo.isLowPowerModeEnabled + thermalState**
- Only tells us low-power mode, not AC vs battery.
- Not sufficient for our needs.

**Recommendation: Option A.** We need `isACPowered` to suppress notifications on AC.

The check is cheap (single IOKit call) and can run once per poll cycle. We only need a boolean — the rest of the battery info (capacity, voltage) is deferred to a future bead.

### Baseline Calculation

**Simple rolling average:** Keep a ring buffer of the last N system power readings. The baseline is the average of this buffer.

```swift
struct PowerBaseline {
    private var buffer: [Double]  // System watts readings
    private var index: Int = 0
    private(set) var count: Int = 0
    let capacity: Int  // e.g., 200 samples = ~10 minutes at 3s intervals

    mutating func append(_ watts: Double)
    var average: Double  // Rolling average
    var isWarmed: Bool { count >= capacity / 2 }  // Need at least half the buffer before triggering
}
```

**Why not a time-weighted average?** Simplicity. All samples come at ~3s intervals (the poll timer), so an unweighted average over the buffer is effectively time-weighted. Timer coalescing can stretch intervals slightly, but the effect on the average is negligible.

**Buffer size:** 200 samples × 3s = 10 minutes of history. This gives a baseline that reflects "what the Mac has been doing for the last 10 minutes." Short enough to adapt to activity changes (starting a build session), long enough to smooth out transient spikes.

### Alert Logic

```
trigger = currentWatts > baseline.average * multiplier
```

Where:
- `multiplier = 2.0` (default) — "your Mac is drawing 2x its recent average"
- Only evaluate when `baseline.isWarmed` (enough history to be meaningful)
- Only evaluate when `isOnBattery` (suppress on AC)
- **Sustained check:** The condition must hold for `N` consecutive poll cycles (e.g., 40 cycles = ~2 minutes at 3s) to avoid notification spam from transient spikes
- **Cooldown:** After firing a notification, suppress for 10 minutes (even if drain remains high). The user already knows.

### Notification Content

```
Title: "Lowbeer — High Battery Drain"
Body: "Your Mac is using 18W (3x normal). Top culprit: node (Claude Code) at 180% CPU for 12 min."
Actions: [Throttle It] [Dismiss]
```

The body includes:
1. Current system watts
2. Multiplier relative to baseline ("3x normal")
3. Top energy consumer from `EnergyLedger.topConsumers.first`
4. That process's CPU% and how long it's been active (`sampleCount * pollInterval`)

The "Throttle It" action maps to `ThrottleEngine.throttle(pid:)` for the top culprit's PID. This reuses the existing `onThrottleApproved` callback pattern from NotificationManager.

### Where It Lives

`DrainDetector` is a new file in `Lowbeer/Core/`. It's initialized and called from the same place as `ThrottleEngine.evaluate()` — either in `LowbeerApp.startMonitoring()` or in the existing evaluate timer.

---

## Edge Cases

1. **Mac wakes from sleep:** System watts spike briefly as processes resume. The sustained-check (2 min) prevents false alarms — the spike settles within seconds.

2. **User plugs in AC mid-drain:** Notification suppresses immediately. If already displayed, the notification is stale but harmless.

3. **Multiple processes share blame:** We show only the top culprit to keep the notification concise. The battery detective popover (future: Lowbeer-q0a) will show the full breakdown.

4. **Baseline cold start:** On first launch, the baseline buffer is empty. `isWarmed` prevents triggering until we have ~5 minutes of data.

5. **User changes poll interval:** The baseline buffer adapts automatically — it's count-based, not time-based. Longer intervals mean a longer time window for the same buffer size.

6. **System is genuinely under heavy load (build, video render):** The 2x multiplier relative to recent baseline means it adapts. If the user has been building for 20 minutes at 15W, the baseline is ~15W, so a new spike would need to hit 30W to trigger. This is by design — we only alert for *unexpected* drain.

---

## What This Bead Does NOT Include

- **Battery detective popover view** → Lowbeer-q0a
- **Battery capacity / health monitoring** → Future
- **Historical drain comparison** → Future (requires persistence)
- **Settings UI for drain alert threshold** → Future (hardcode 2x for v1)
- **Per-process drain notifications** → This fires for system-level drain only

---

## Open Questions

1. **Should we show the notification as a banner or alert?** Banners auto-dismiss; alerts stay until the user acts. For a battery drain, a banner is less intrusive. The user can always check the menu bar for details.

2. **Should the cooldown reset if drain subsides and returns?** Current design: cooldown is absolute (10 min). If drain drops to normal and spikes again within 10 min, no re-notification. This prevents a chatty experience for intermittent high load. The user can check the menu bar if curious.

3. **IOKit framework linking:** We currently use dlsym for IOReport (private API). IOPSCopyPowerSourcesInfo is a public C API in IOKit. We can either link IOKit directly or dlsym it. Since it's public API, direct linking is cleaner and safe.
