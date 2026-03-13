# Plan: Per-Process Energy Tracker

**Date:** 2026-03-12
**Bead:** Lowbeer-eck
**PRD:** docs/prds/2026-03-12-per-process-energy-tracker.md

---

## Step 1: Create EnergyLedger.swift

**File:** `Lowbeer/Core/EnergyLedger.swift`

Create the `EnergyEntry` struct and `EnergyLedger` class:

```swift
import AppKit
import Foundation

/// Per-app cumulative energy measurement.
struct EnergyEntry {
    let identity: String           // bundleID ?? path
    var displayName: String        // Human-readable name
    var cumulativeWh: Double = 0   // Total watt-hours in the rolling window
    var lastWatts: Double = 0      // Most recent instantaneous watts
    var peakWatts: Double = 0      // Highest instantaneous watts seen
    var lastSeen: Date = Date()    // For rolling window eviction
    var sampleCount: Int = 0       // Number of poll cycles recorded
    var icon: NSImage?             // Cached app icon
}

@Observable
final class EnergyLedger {
    private(set) var entries: [String: EnergyEntry] = [:]

    /// Rolling window duration (24 hours).
    let windowDuration: TimeInterval = 24 * 3600

    /// Record a poll cycle measurement for one process.
    func record(identity: String, displayName: String, watts: Double,
                whIncrement: Double, icon: NSImage?) {
        var entry = entries[identity] ?? EnergyEntry(identity: identity, displayName: displayName)
        entry.cumulativeWh += whIncrement
        entry.lastWatts = watts
        entry.peakWatts = max(entry.peakWatts, watts)
        entry.lastSeen = Date()
        entry.sampleCount += 1
        entry.displayName = displayName
        if entry.icon == nil { entry.icon = icon }
        entries[identity] = entry
    }

    /// Remove entries not seen within the rolling window.
    func evictStale() {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        entries = entries.filter { $0.value.lastSeen > cutoff }
    }

    /// Entries sorted by cumulative Wh descending. For UI consumers.
    var topConsumers: [EnergyEntry] {
        entries.values.sorted { $0.cumulativeWh > $1.cumulativeWh }
    }

    /// Total energy tracked across all entries.
    var totalWh: Double {
        entries.values.reduce(0) { $0 + $1.cumulativeWh }
    }
}
```

**Verification:** File compiles. No external dependencies.

---

## Step 2: Add currentWatts to ProcessInfo

**File:** `Lowbeer/Models/ProcessInfo.swift`

Add one property:

```swift
var currentWatts: Double? = nil   // Per-process watts estimate from last poll
```

This goes alongside the existing `cpuPercent`, `isThrottled`, etc. Views can display it inline.

**Verification:** Existing views that use ProcessInfo are unaffected (new property is optional, defaults to nil).

---

## Step 3: Integrate into ProcessMonitor.poll()

**File:** `Lowbeer/Core/ProcessMonitor.swift`

Changes:

1. Add property: `let energyLedger = EnergyLedger()`

2. At the end of `poll()`, after `updated` is built and `power` is sampled, before the `DispatchQueue.main.async` block, add accumulation logic:

```swift
// Energy accumulation
let systemWatts = power.totalWatts
if systemWatts >= 1.0, total >= 1.0 {
    for process in updated {
        let share = process.cpuPercent / total
        let processWatts = share * systemWatts
        let whIncrement = processWatts * (pollInterval / 3600.0)

        process.currentWatts = processWatts

        energyLedger.record(
            identity: process.bundleIdentifier ?? process.path,
            displayName: process.name,
            watts: processWatts,
            whIncrement: whIncrement,
            icon: process.icon
        )
    }
    energyLedger.evictStale()
} else {
    // Below threshold — clear instantaneous watts
    for process in updated {
        process.currentWatts = nil
    }
}
```

**Important:** This runs inside `poll()` before the main-thread dispatch, so `energyLedger` mutations happen on the timer callback thread. Since `@Observable` tracks access, and views read on main thread, we need to move the ledger update into the `DispatchQueue.main.async` block alongside `self?.processes = updated`.

Revised: move the accumulation into the main-thread async block:

```swift
DispatchQueue.main.async { [weak self] in
    guard let self else { return }
    self.processes = updated
    self.totalCPU = total
    self.latestPower = power

    // Energy accumulation (on main thread with observable state)
    let systemWatts = power.totalWatts
    if systemWatts >= 1.0, total >= 1.0 {
        for process in updated {
            let share = process.cpuPercent / total
            let processWatts = share * systemWatts
            let whIncrement = processWatts * (self.pollInterval / 3600.0)
            process.currentWatts = processWatts

            self.energyLedger.record(
                identity: process.bundleIdentifier ?? process.path,
                displayName: process.name,
                watts: processWatts,
                whIncrement: whIncrement,
                icon: process.icon
            )
        }
        self.energyLedger.evictStale()
    }
}
```

**Verification:**
- Run `yes > /dev/null &` then check `energyLedger.entries` has an entry for `/usr/bin/yes` with growing `cumulativeWh`
- Build succeeds with no warnings
- ProcessMonitor poll timing unchanged

---

## Step 4: Update Xcode project

**File:** `Lowbeer.xcodeproj`

Add `Lowbeer/Core/EnergyLedger.swift` to the Xcode project. Run the xcodeproj generator:

```bash
ruby /tmp/gen_xcodeproj.rb
```

**Verification:** `xcodebuild build` succeeds.

---

## Step 5: Build and smoke test

```bash
xcodebuild -project Lowbeer.xcodeproj -scheme Lowbeer -configuration Debug build
```

Then launch, verify:
1. Menu bar still shows watts correctly
2. No crashes or performance regression
3. Process list renders normally

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| Thread safety: ledger mutated off main thread | Move accumulation into DispatchQueue.main.async block |
| Sleep/wake inflated delta | Timer doesn't fire during sleep; deltaTime should be ~pollInterval |
| Division by zero (totalCPU = 0) | Guard: skip when total < 1% |
| Memory growth | 24h eviction caps at ~hundreds of entries max |
