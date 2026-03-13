# PRD: Per-Process Energy Tracker

**Date:** 2026-03-12
**Bead:** Lowbeer-eck
**Priority:** P0
**Parent:** Lowbeer-waw (Battery detective epic)
**Blocks:** Lowbeer-1yd (smart notification), Lowbeer-q0a (detective view), Lowbeer-dni (leaderboard), Lowbeer-squ (savings counter)

---

## Problem

Lowbeer shows real-time system power (via IOReport) and per-process CPU% (via libproc), but cannot answer "how much energy has this app consumed over time?" The energy share shown in ProcessRowView (`share%⚡`) is an ephemeral per-frame proportion — it has no memory. Without cumulative per-app energy data, the downstream Battery Detective features (leaderboard, savings counter, drain notifications) have nothing to build on.

## Solution

Add an `EnergyLedger` that accumulates per-app energy estimates over a rolling 24-hour window. Each poll cycle, multiply each process's CPU share by system watts to get per-process watts, then accumulate into watt-hours keyed by app identity.

## Requirements

### Must Have

1. **EnergyLedger class** — `@Observable`, keyed by app identity (`bundleIdentifier ?? path`), stores cumulative Wh, last-seen timestamp, peak watts, sample count per entry
2. **Per-poll accumulation** — At the end of each `ProcessMonitor.poll()` cycle, compute per-process watts and increment Wh on the corresponding ledger entry
3. **Rolling 24h window** — Evict entries not seen in 24 hours to bound memory
4. **Guards against bad data** — Skip accumulation when `totalCPU < 1%` or `systemWatts < 1W` (idle/unstable conditions)
5. **ProcessInfo augmentation** — Add `currentWatts: Double?` to ProcessInfo for per-PID instantaneous watts display
6. **Public API for views** — Sorted accessor returning entries ranked by cumulative Wh (descending) for downstream UI consumers

### Nice to Have

4. **Persistence** — Save/load ledger to JSON file periodically (every 5 min) for cross-restart continuity. Defer to v2.
5. **GPU-aware attribution** — Detect GPU-heavy processes and weight their energy share. Defer — requires IOAccelerator private API.

### Out of Scope

- Popover UI changes (Lowbeer-q0a)
- Notification logic (Lowbeer-1yd)
- Savings counter (Lowbeer-squ)
- Leaderboard view (Lowbeer-dni)
- Battery discharge rate monitoring (future)

## Design

### New Files

| File | Purpose |
|------|---------|
| `Lowbeer/Core/EnergyLedger.swift` | EnergyLedger class + EnergyEntry struct |

### Modified Files

| File | Change |
|------|--------|
| `Lowbeer/Core/ProcessMonitor.swift` | Add `energyLedger` property, call `record()` and `evictStale()` at end of `poll()` |
| `Lowbeer/Models/ProcessInfo.swift` | Add `currentWatts: Double?` property |

### Data Flow

```
ProcessMonitor.poll()
  ├── ProcessSampler.sampleAll()     → per-process CPU%
  ├── PowerSampler.sample()          → system watts
  └── EnergyLedger.record()          → per-app Wh accumulation
       └── EnergyEntry.cumulativeWh += (share × watts × dt/3600)
```

### App Identity

Key: `bundleIdentifier ?? path`

- GUI apps: bundle ID (e.g., `com.google.Chrome`)
- CLI tools: executable path (e.g., `/usr/local/bin/node`)
- Multiple PIDs with same identity are merged into one entry (this is correct — the user thinks of "Chrome" as one thing regardless of helper processes)

### Thread Safety

`EnergyLedger` is updated on the same thread as `poll()` and read from the main thread via `@Observable`. Since `poll()` dispatches its results to `DispatchQueue.main.async`, the ledger update should happen inside the same main-thread dispatch to avoid races.

## Success Criteria

1. After running Lowbeer for 10 minutes with a CPU-intensive process (e.g., `yes > /dev/null`), `energyLedger.entries` contains an entry for that process with `cumulativeWh > 0`
2. The `cumulativeWh` value is proportional to the process's CPU share × system watts × elapsed time
3. Entries for processes that exit are retained for 24 hours
4. Memory usage does not grow unbounded (entries are evicted after 24h)
5. No regression in poll() performance (< 1ms added overhead)
