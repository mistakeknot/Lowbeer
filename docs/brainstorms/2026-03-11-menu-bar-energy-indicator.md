# Menu Bar Energy Indicator — Brainstorm

**Date:** 2026-03-11
**Bead:** Lowbeer-iqr
**Parent:** Lowbeer-waw (Battery Detective epic)
**Dependency:** Lowbeer-4ue (IOReport bindings) — DONE

---

## The Problem

Lowbeer's menu bar currently shows a flame icon + total CPU%. This tells you "processes are busy" but not "your battery is draining fast." CPU% is a poor proxy for power — 100% on E-cores draws ~1W while 100% on a single P-core draws ~3W. The user needs to see actual system power draw at a glance.

## What We're Building

Replace the CPU% display with a live system wattage reading from PowerSampler (IOReport). The menu bar should answer one question: **"Is my Mac using a lot of power right now?"**

## Design Options

### Option A: Numeric Wattage
`⚡ 4.2W` — simple, precise, space-efficient.
- Pro: Exact, easy to compare over time, expert-friendly
- Con: Most users don't know if 4.2W is good or bad

### Option B: Color-Coded Dot
Green/yellow/red dot based on thresholds.
- Pro: Instantly interpretable, minimal space
- Con: Loses precision, thresholds are arbitrary

### Option C: Both (Recommended)
`⚡ 4.2W` with the bolt color indicating severity:
- Green: < 5W (idle/light use)
- Yellow: 5-15W (moderate use)
- Red: > 15W (heavy drain)
- Pro: Precision + at-a-glance severity
- Con: Slightly more visual noise

### Option D: Adaptive Display
Show wattage only when power exceeds a threshold (e.g., > 3W). Below that, show nothing or just the bolt. Prevents visual noise during idle.

**Recommendation:** Option C with Option D behavior — show colored `⚡ 4.2W` when drawing > 3W, just a green `⚡` when idle. This keeps the menu bar clean when nothing interesting is happening.

## Integration Points

### PowerSampler in the poll cycle
PowerSampler needs to be called each poll cycle (every 3s, matching ProcessMonitor). Two approaches:

1. **ProcessMonitor calls PowerSampler** — add a `powerSampler` property to ProcessMonitor. Each `poll()` also calls `powerSampler.sample()`. Pro: single timer, guaranteed synchronization.

2. **LowbeerApp holds PowerSampler separately** — PowerSampler lives on LowbeerApp, sampled on the same timer. Con: two objects to coordinate.

**Recommendation:** Option 1. ProcessMonitor already owns the poll cycle. Adding PowerSampler there keeps the sampling synchronized — we want CPU% and power readings from the same moment.

### Menu bar label update
Currently `menuBarLabel` reads `monitor.totalCPU`. We add `monitor.latestPower` (a `PowerSample`) and display watts instead of / alongside CPU%.

### Fallback (Intel/no IOReport)
When `isIOReportAvailable == false`, fall back to current CPU% display. No change from today's behavior.

## Thresholds

Based on Apple Silicon power measurements and real-world usage:

| State | Watts | Color | Typical Activity |
|-------|-------|-------|-----------------|
| Idle | < 3W | — | Just bolt icon, no number |
| Light | 3-5W | Green | Web browsing, editing |
| Moderate | 5-10W | Yellow | Compiling, video playback |
| Heavy | 10-20W | Orange | Multi-threaded builds, AI inference |
| Extreme | > 20W | Red | Full GPU + CPU load |

These work for M1/M2/M3 base chips. Pro/Max/Ultra chips draw more — we may want to adjust thresholds based on chip family later, but fixed thresholds are fine for v1.

## Implementation Sketch

### ProcessMonitor changes
```swift
// New properties
private(set) var powerSampler = PowerSampler()
@Published private(set) var latestPower: PowerSample = .zero

// In poll():
let power = powerSampler.sample()
DispatchQueue.main.async {
    self.latestPower = power
}
```

### LowbeerApp menuBarLabel changes
```swift
private var menuBarLabel: some View {
    HStack(spacing: 2) {
        Image(systemName: "bolt.fill")
            .foregroundStyle(powerColor)
        if monitor.latestPower.totalWatts >= 3.0 {
            Text(String(format: "%.1fW", monitor.latestPower.totalWatts))
                .font(.system(.caption2, design: .monospaced))
        }
    }
    .onAppear { startMonitoring() }
}

private var powerColor: Color {
    let watts = monitor.latestPower.totalWatts
    if watts < 3 { return .green }
    if watts < 5 { return .green }
    if watts < 10 { return .yellow }
    if watts < 20 { return .orange }
    return .red
}
```

### Icon choice
- Current: `flame` (SF Symbols)
- Proposed: `bolt.fill` — universally associated with power/energy
- Alternative: `bolt.batteryblock.fill` — more specific but larger

## Open Questions

1. **Should we keep CPU% alongside wattage?** Could show both: `⚡ 4.2W · 23%`. But this might be too much for the menu bar. The popover already shows per-process CPU%. Recommendation: wattage only in menu bar, CPU% in popover.

2. **Wattage precision:** `4.2W` (1 decimal) is enough. `4W` (integer) loses useful precision. `4.23W` (2 decimals) is visual noise.

3. **Update frequency:** PowerSampler needs >100ms between samples (guard in `sample()`). Our 3s poll interval is fine. Faster updates would show more jitter without adding information.
