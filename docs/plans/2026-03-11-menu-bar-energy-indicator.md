# Plan: Menu Bar Energy Indicator

**Bead:** Lowbeer-iqr
**Brainstorm:** docs/brainstorms/2026-03-11-menu-bar-energy-indicator.md
**Complexity:** 3/5 (moderate)

---

## Goal

Replace the current CPU% menu bar display with live system wattage from IOReport. Show colored `⚡ 4.2W` when power > 3W, just a green `⚡` when idle. Fall back to current CPU% display on Intel/CI where IOReport is unavailable.

## Steps

### Step 1: Add PowerSampler to ProcessMonitor

**File:** `Lowbeer/Core/ProcessMonitor.swift`

1. Add `PowerSampler` as a property of `ProcessMonitor`
2. Add `@Observable`-compatible `latestPower: PowerSample` property
3. Call `powerSampler.sample()` at the end of each `poll()` cycle
4. Update `latestPower` on the main queue alongside `processes` and `totalCPU`

**Why in ProcessMonitor:** Keeps power and CPU sampling synchronized on the same timer. No second timer needed.

### Step 2: Update menu bar label

**File:** `Lowbeer/App/LowbeerApp.swift`

1. Change `menuBarLabel` to show wattage from `monitor.latestPower`
2. When `monitor.powerSampler.isIOReportAvailable`:
   - Show `bolt.fill` icon with color based on wattage thresholds
   - Show `"%.1fW"` text when totalWatts >= 3.0
   - Hide text (just show green bolt) when < 3.0W
3. When IOReport unavailable (fallback):
   - Keep current `flame` icon + CPU% display unchanged

**Color thresholds:**
- < 5W → green
- 5-10W → yellow
- 10-20W → orange
- >= 20W → red

### Step 3: Add tests

**File:** `LowbeerTests/Core/ProcessMonitorTests.swift` (new or extend existing)

1. Test that ProcessMonitor initializes PowerSampler
2. Test that `latestPower` starts at `.zero`
3. Test PowerSample color threshold logic (extract to a helper if needed)

### Step 4: Build and verify

1. `xcodebuild build` — verify compilation
2. `xcodebuild test` — run full test suite
3. Manual check: launch app, verify menu bar shows wattage

## Files Changed

| File | Change |
|------|--------|
| `Lowbeer/Core/ProcessMonitor.swift` | Add PowerSampler integration |
| `Lowbeer/App/LowbeerApp.swift` | Update menuBarLabel to show wattage |
| `LowbeerTests/Core/ProcessMonitorTests.swift` | New tests for power integration |

## Risks

- **IOReport sampling on utility queue:** PowerSampler uses dlsym/CFDictionary. Should be safe on a background queue but watch for thread-safety issues with IOReport's subscription model. Mitigation: PowerSampler is already designed for single-threaded use — call it on the same queue as poll().
- **Menu bar label size:** `⚡ 12.3W` is wider than `🔥 23%`. Should fit fine — macOS menu bar items auto-size, and SF Symbols + 5 chars of text is standard.

## Non-Goals

- Per-process energy attribution (that's Lowbeer-eck)
- Settings for thresholds (hardcode for now)
- Historical power graph (future popover enhancement)
