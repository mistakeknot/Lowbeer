# Per-Process Energy Tracker — Brainstorm

**Date:** 2026-03-12
**Bead:** Lowbeer-eck
**Parent:** Lowbeer-waw (Battery detective epic)
**Depends on:** Lowbeer-4ue (IOReport Swift bindings) — DONE

---

## The Goal

Accumulate per-process energy estimates over time so we can answer: "How much energy has Chrome/node/Xcode used in the last 24 hours?" This is the data layer that powers the offender leaderboard (Lowbeer-dni), battery savings counter (Lowbeer-squ), and battery detective popover (Lowbeer-q0a).

Currently `ProcessRowView` computes energy share ephemerally each frame: `(processCPU / totalCPU) * 100%`. That's a relative proportion, not a cumulative measurement. We need to go from "Chrome is 40% of current load" to "Chrome has used 0.82 Wh in the last 4 hours."

---

## What We Already Have

| Component | State | What it provides |
|-----------|-------|-----------------|
| `ProcessMonitor.poll()` | Working | Per-process CPU% every 3s, top 50 processes |
| `PowerSampler.sample()` | Working | System-level watts via IOReport (CPU, GPU, ANE, DRAM) |
| `ProcessInfo` | Working | Per-process model with history ring buffer |
| `ProcessRowView` | Working | Ephemeral energy share display (`share%⚡`) |
| `ProcessHistory` | Working | Fixed-size ring buffer (~3 min at 3s intervals) |

The key insight: **every poll cycle already produces both per-process CPU% and system watts**. We just need to multiply, accumulate, and persist.

---

## Energy Estimation Formula

Each poll cycle:

```
process_watts = (process_cpu% / total_cpu%) × system_total_watts
process_wh_increment = process_watts × (poll_interval_seconds / 3600)
cumulative_wh += process_wh_increment
```

**Why this works:** IOReport gives us accurate system-level watts. CPU% proportion tells us each process's share of that power. The product is a reasonable per-process watts estimate. Accumulated over time, rounding errors smooth out.

**Known limitations:**
- GPU-heavy processes (e.g., games, video rendering) may have low CPU% but high energy. Their GPU contribution gets spread across CPU-active processes instead. Acceptable for v1 — most "runaway" processes are CPU-bound.
- ANE/DRAM energy is included in the total but attributed by CPU share. Good enough for ranking, slightly unfair to pure-CPU processes.
- When `total_cpu%` is near zero (idle system), the fraction is unstable. Guard: skip accumulation when system total < 1% or system watts < 1W.

---

## App Identity: The Key Challenge

Processes come and go. PIDs are reused. We need to accumulate energy by **app identity**, not by PID.

**Identity key options:**

| Key | Pros | Cons |
|-----|------|------|
| PID | Unique to a running instance | Reused after exit; can't accumulate across restarts |
| Bundle ID | Stable across restarts, canonical | CLI tools don't have one |
| Executable path | Works for everything | Same binary can have different purposes (e.g., `/usr/bin/python3`) |
| Name + bundle ID (fallback to path) | Best coverage | Needs dedup logic |

**Recommended:** Composite identity keyed on `bundleIdentifier ?? path`. This matches how `AppIdentity` already works in the rule system. We can store cumulative data in a dictionary keyed by this string.

For processes like `node` or `python3` where path is the same but the workload differs: accept that they'll be grouped. The user thinks of "node" as one thing anyway.

---

## Data Structure Design

### EnergyLedger — The Accumulator

A new class that ProcessMonitor updates each poll cycle and that views read from.

```swift
@Observable
final class EnergyLedger {
    // Keyed by app identity string (bundleID ?? path)
    private(set) var entries: [String: EnergyEntry] = [:]

    // Rolling window: evict entries not seen in 24 hours
    let windowDuration: TimeInterval = 24 * 3600
}

struct EnergyEntry {
    let identity: String          // Key
    let displayName: String       // Human-readable name
    var cumulativeWh: Double      // Total Wh in the window
    var lastSeen: Date            // For eviction
    var lastWatts: Double         // Most recent instantaneous watts
    var sampleCount: Int          // Number of poll cycles recorded
    var peakWatts: Double         // Highest instantaneous watts seen
    var icon: NSImage?            // Cached app icon
}
```

### Where It Lives

`EnergyLedger` is owned by `ProcessMonitor` (or a peer object initialized in `LowbeerApp`). Updated during `poll()` after CPU% and power are computed.

### Rolling Window Eviction

Every poll cycle (or every N cycles to reduce overhead), sweep entries where `Date().timeIntervalSince(entry.lastSeen) > windowDuration`. This keeps memory bounded — a 24h window with 3s samples and ~50 active apps ≈ 50 entries, negligible memory.

---

## Integration Points

### 1. ProcessMonitor.poll() — Accumulate

After computing CPU% and power, add an accumulation step:

```swift
// In poll(), after `updated` array is built and power sampled:
let systemWatts = power.totalWatts
let totalCPUPct = total  // sum of all process CPU%

if systemWatts >= 1.0, totalCPUPct >= 1.0 {
    for process in updated {
        let share = process.cpuPercent / totalCPUPct
        let processWatts = share * systemWatts
        let whIncrement = processWatts * (pollInterval / 3600.0)

        energyLedger.record(
            identity: process.bundleIdentifier ?? process.path,
            displayName: process.name,
            watts: processWatts,
            whIncrement: whIncrement,
            icon: process.icon
        )
    }
    energyLedger.evictStale()
}
```

### 2. ProcessInfo — Add Energy Reference

Add an optional reference back to the energy entry so views can show cumulative data:

```swift
// On ProcessInfo:
var cumulativeWh: Double?   // Set from EnergyLedger lookup each poll
var currentWatts: Double?   // Instantaneous per-process watts estimate
```

### 3. PopoverView / ProcessRowView — Display

Replace the ephemeral `share%⚡` with actual watts:

```
Chrome      45.2%  ⚡ 5.4W  (0.82 Wh)    [sparkline] [⏸]
node        120.3% ⚡ 8.1W  (2.14 Wh)    [sparkline] [⏸]
```

Or for a leaderboard view (battery detective):
```
Top Energy Consumers (24h)
1. node          2.14 Wh   ████████████
2. Chrome        0.82 Wh   █████
3. Xcode         0.41 Wh   ██
```

### 4. Menu Bar — Optional Cumulative Display

The menu bar already shows `⚡ 12.5W`. Could add a total daily Wh if useful, but probably too noisy for the menu bar. Keep it as system watts.

---

## Persistence: Do We Need It?

**For v1: No.** The energy ledger is in-memory only. When Lowbeer quits, the ledger resets. This is acceptable because:
- Lowbeer is a menu bar app that runs continuously
- The 24h window means data is inherently transient
- Persistence adds complexity (file format, migration, corruption handling)

**For v2 (future):** Persist to a lightweight file (JSON or plist) on a timer (every 5 minutes). Load on startup. This enables "yesterday's energy report" and cross-restart continuity.

---

## What This Bead Does NOT Include

- **Notification on abnormal drain** → Lowbeer-1yd (depends on this bead)
- **Battery detective popover view** → Lowbeer-q0a (depends on this bead)
- **Daily savings counter** → Lowbeer-squ (depends on this bead)
- **Offender leaderboard in popover** → Lowbeer-dni (depends on this bead)
- **Battery discharge rate monitoring** → Future (IOPSCopyPowerSourcesInfo)

This bead is purely the **data accumulation layer**. It produces `EnergyLedger` with per-app Wh data. Downstream beads consume it for UI and notifications.

---

## Implementation Approach

### Option A: Ledger Inside ProcessMonitor

Add `EnergyLedger` as a property of `ProcessMonitor`. Update it at the end of `poll()`. Simplest — no new wiring, no additional timers.

**Pro:** Single poll loop, no synchronization concerns.
**Con:** ProcessMonitor gets bigger. But it's already the natural home for "per-poll-cycle data accumulation."

### Option B: Separate EnergyTracker Observer

Create `EnergyTracker` that observes `ProcessMonitor.processes` and `ProcessMonitor.latestPower`. Each time they update, it runs the accumulation.

**Pro:** Clean separation of concerns.
**Con:** Observation timing — SwiftUI @Observable doesn't guarantee you see both `processes` and `latestPower` in the same update cycle. Could get stale power data.

### Recommendation: Option A

ProcessMonitor already owns both CPU% and power data. Adding 10 lines of accumulation logic at the end of `poll()` is the simplest path. The `EnergyLedger` class itself is a separate file, keeping the data model clean.

---

## Open Questions

1. **Should `currentWatts` be on ProcessInfo or only on EnergyEntry?** Putting it on ProcessInfo means views can show it inline. But ProcessInfo is per-PID while EnergyEntry is per-identity. Multiple PIDs could map to the same identity. Recommendation: put `currentWatts` on ProcessInfo (it's the per-PID estimate) and `cumulativeWh` on EnergyEntry (it's the accumulated total for that app).

2. **GPU attribution:** When a process uses Metal/GPU heavily but little CPU, it'll show low energy share. Should we try to detect GPU-using processes? Probably not for v1 — it requires IOAccelerator private API and adds significant complexity for a niche case.

3. **Display format:** Wh is technically correct but unfamiliar to most users. Alternative: "mAh" (needs voltage assumption) or just "energy score" (unitless). Recommendation: Use Wh — it's the SI unit, and power users (our target) understand it. Add a tooltip explaining it for newcomers.

4. **Accumulation guard:** When the Mac sleeps and wakes, there's a large time delta but no actual work done. ProcessMonitor's poll timer doesn't fire during sleep, so `deltaTime` in poll() should be ~3s even after wake. But verify this — if a poll fires immediately on wake with a large deltaTime, the Wh increment would be inflated.
