# Plan: Smart Battery Drain Notification

**Date:** 2026-03-12
**Bead:** Lowbeer-1yd
**PRD:** docs/prds/2026-03-12-smart-battery-drain-notification.md

---

## Step 1: Create DrainDetector.swift

**File:** `Lowbeer/Core/DrainDetector.swift`

Contains three components:

### 1a. PowerBaseline (struct)

Ring buffer of system watts readings for rolling average:

```swift
struct PowerBaseline {
    private var buffer: [Double]
    private var index: Int = 0
    private(set) var count: Int = 0
    let capacity: Int

    init(capacity: Int = 200) {
        self.capacity = capacity
        self.buffer = Array(repeating: 0, count: capacity)
    }

    mutating func append(_ watts: Double) {
        buffer[index] = watts
        index = (index + 1) % capacity
        if count < capacity { count += 1 }
    }

    var average: Double {
        guard count > 0 else { return 0 }
        let samples = count < capacity ? Array(buffer[0..<count]) : buffer
        return samples.reduce(0, +) / Double(count)
    }

    /// Need at least half the buffer before triggering alerts.
    var isWarmed: Bool { count >= capacity / 2 }
}
```

### 1b. BatteryState (enum with static method)

Detect AC vs battery using IOPSCopyPowerSourcesInfo:

```swift
import IOKit.ps

enum BatteryState {
    static var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let firstSource = sources.first,
              let desc = IOPSGetPowerSourceDescription(snapshot, firstSource as CFTypeRef)?
                  .takeUnretainedValue() as? [String: Any]
        else {
            return false  // Can't determine — assume AC (safe default)
        }
        let powerSource = desc[kIOPSPowerSourceStateKey as String] as? String
        return powerSource == kIOPSBatteryPowerValue as String
    }
}
```

### 1c. DrainDetector (class)

Main detection logic:

```swift
@MainActor
final class DrainDetector {
    private var baseline = PowerBaseline()
    private var sustainedCount: Int = 0
    private var lastAlertTime: Date?
    private let multiplierThreshold: Double = 2.0
    private let sustainedCycles: Int = 40  // ~2 min at 3s intervals
    private let cooldownInterval: TimeInterval = 600  // 10 minutes

    func evaluate(
        systemWatts: Double,
        topProcess: ProcessInfo?,
        energyLedger: EnergyLedger,
        notificationsEnabled: Bool
    ) {
        baseline.append(systemWatts)

        guard notificationsEnabled,
              baseline.isWarmed,
              BatteryState.isOnBattery
        else {
            sustainedCount = 0
            return
        }

        let avg = baseline.average
        guard avg > 1.0, systemWatts > avg * multiplierThreshold else {
            sustainedCount = 0
            return
        }

        sustainedCount += 1
        guard sustainedCount >= sustainedCycles else { return }

        // Cooldown check
        if let last = lastAlertTime,
           Date().timeIntervalSince(last) < cooldownInterval {
            return
        }

        // Fire notification
        let multiplier = systemWatts / avg
        let culprit = energyLedger.topConsumers.first
        let culpritProcess = topProcess  // The highest-CPU process

        LowbeerNotificationManager.shared.notifyDrain(
            systemWatts: systemWatts,
            multiplier: multiplier,
            culpritName: culprit?.displayName ?? culpritProcess?.name ?? "Unknown",
            culpritCPU: culpritProcess?.cpuPercent ?? 0,
            culpritPID: culpritProcess?.pid ?? 0,
            culpritDuration: culprit.map { Double($0.sampleCount) * 3.0 }  // Approximate
        )

        lastAlertTime = Date()
        sustainedCount = 0  // Reset after firing
    }
}
```

**Verification:** File compiles. IOKit framework linked.

---

## Step 2: Add notifyDrain to NotificationManager

**File:** `Lowbeer/Core/NotificationManager.swift`

Add a new notification category and method:

1. Add category constant: `drainCategoryID = "DRAIN_ALERT"`
2. Add throttle action for drain: reuse existing `THROTTLE_ACTION`
3. Register the new category in `setup()` alongside the existing `askCategory`
4. Add method:

```swift
func notifyDrain(
    systemWatts: Double,
    multiplier: Double,
    culpritName: String,
    culpritCPU: Double,
    culpritPID: pid_t,
    culpritDuration: Double?
) {
    let content = UNMutableNotificationContent()
    content.title = "Lowbeer — High Battery Drain"

    var body = String(format: "Your Mac is using %.0fW (%.0fx normal).", systemWatts, multiplier)
    body += " Top culprit: \(culpritName) at \(Int(culpritCPU))% CPU"
    if let dur = culpritDuration, dur > 60 {
        body += String(format: " for %.0f min", dur / 60)
    }
    body += "."
    content.body = body

    content.sound = .default
    content.categoryIdentifier = Self.drainCategoryID
    content.userInfo = ["pid": Int(culpritPID)]

    let request = UNNotificationRequest(
        identifier: "drain-\(Date().timeIntervalSince1970)",
        content: content,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
}
```

The existing `didReceive` handler already handles `THROTTLE_ACTION` for any category — it reads the PID from userInfo and calls `onThrottleApproved`. So no change needed there, just ensure the new category also includes the throttle+ignore actions.

---

## Step 3: Integrate into ProcessMonitor.poll()

**File:** `Lowbeer/Core/ProcessMonitor.swift`

1. Add property: `let drainDetector = DrainDetector()`
2. At the end of the `DispatchQueue.main.async` block (after energy accumulation), add:

```swift
// Drain detection (after energy accumulation)
self.drainDetector.evaluate(
    systemWatts: systemWatts,
    topProcess: displayProcesses.first,
    energyLedger: self.energyLedger,
    notificationsEnabled: LowbeerSettings.shared.notificationsEnabled
)
```

Note: `drainDetector.evaluate()` always runs (even when below the energy threshold), because the baseline needs continuous feeding. The guards inside `evaluate()` handle the "below threshold" case by resetting `sustainedCount`.

Actually — we need the baseline to always append, but the evaluate logic should only check when conditions are met. Let me restructure: always call `evaluate()` with the raw system watts (not the clamped version), and let evaluate handle everything internally.

Revised call site:
```swift
self.drainDetector.evaluate(
    systemWatts: power.totalWatts,
    topProcess: displayProcesses.first,
    energyLedger: self.energyLedger,
    notificationsEnabled: LowbeerSettings.shared.notificationsEnabled
)
```

---

## Step 4: Update Xcode project

**File:** `Lowbeer.xcodeproj/project.pbxproj`

1. Add `DrainDetector.swift` file reference and build phase entry (same pattern as EnergyLedger)
2. Link `IOKit.framework` to the Lowbeer target

---

## Step 5: Build and smoke test

```bash
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug test
```

Verify:
1. Build succeeds
2. All 84+ tests pass
3. App launches without crash
4. No notification fires immediately on launch (baseline warming)

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| IOPSCopyPowerSourcesInfo unavailable on desktop Mac | Return `false` for `isOnBattery` — no notifications on desktop (correct behavior) |
| Baseline doesn't reflect user's normal usage | 200-sample (10 min) window adapts to current activity level |
| False alarm during legitimate heavy workload | 2x multiplier + 2 min sustained requirement filters transients |
| Notification spam | 10-minute cooldown after each alert |
| IOKit link adds entitlement requirements | IOKit is a system framework, no entitlements needed for public APIs |
