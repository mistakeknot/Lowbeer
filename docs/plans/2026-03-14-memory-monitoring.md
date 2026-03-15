# Plan: Per-Process Memory Monitoring with Anomaly Alerts

**Bead:** Lowbeer-18v
**Date:** 2026-03-14
**Complexity:** 2/5 (simple)

## Goal

Track per-process resident memory alongside CPU. Alert when any process exceeds a configurable threshold (default 10 GB) or grows >2x within a 10-minute window. Uses `pti_resident_size` from the same `proc_taskinfo` call that already provides CPU time.

## Design

Follow the EnergyLedger pattern: a new `MemoryLedger` class that accumulates per-process memory readings each poll cycle, keyed by app identity. Unlike energy (which accumulates Wh), memory tracking records current and peak resident bytes plus a growth-rate ring buffer for anomaly detection.

### Architecture

```
ProcessSnapshot.swift  — already reads proc_taskinfo, just expose resident_size
ProcessMonitor.poll()  — pass resident bytes to MemoryLedger each cycle
MemoryLedger.swift     — track current/peak/growth per identity, flag anomalies
lowbeer-mcp/main.swift — already reads pti_resident_size, add get_memory tool
```

## Steps

### Step 1: Expose resident_size in ProcessSnapshot

**File:** `Lowbeer/Core/ProcessSnapshot.swift`

Add `residentBytes: UInt64` to the `ProcessSnapshot` struct. The `proc_taskinfo` call already reads this — it's `taskInfo.pti_resident_size`.

**Verification:** File compiles.

### Step 2: Create MemoryLedger.swift

**File:** `Lowbeer/Core/MemoryLedger.swift` (NEW)

```swift
@MainActor
@Observable
final class MemoryLedger {
    nonisolated init() {}

    struct MemoryEntry {
        let identity: String
        var displayName: String
        var currentBytes: UInt64 = 0
        var peakBytes: UInt64 = 0
        var lastSeen: Date = Date()
        var icon: NSImage?
        // Ring buffer of last 200 readings (~10 min at 3s) for growth detection
        var history: [UInt64] = []
        var historyIndex: Int = 0
    }

    private(set) var entries: [String: MemoryEntry] = [:]

    /// Anomaly thresholds
    static let absoluteThreshold: UInt64 = 10 * 1024 * 1024 * 1024  // 10 GB
    static let growthMultiplier: Double = 2.0  // 2x growth triggers alert
    static let historyCapacity: Int = 200  // ~10 min at 3s intervals

    func record(identity:displayName:residentBytes:icon:)
    func evictStale()  // Remove entries absent >1 hour
    var topConsumers: [MemoryEntry]  // Sorted by currentBytes desc
    var anomalies: [MemoryEntry]  // Entries exceeding threshold or growth rate
}
```

**Key behaviors:**
- `record()` updates current bytes, peak, appends to history ring buffer
- `anomalies` computed property checks: `currentBytes > absoluteThreshold` OR earliest history reading × growthMultiplier < currentBytes (2x growth in window)
- `evictStale()` removes entries not seen in 1 hour (shorter than energy's 24h — processes come and go faster than apps)

**Verification:** File compiles. `nonisolated init()` pattern matches EnergyLedger.

### Step 3: Add residentBytes to ProcessInfo model

**File:** `Lowbeer/Models/ProcessInfo.swift`

Add `var residentBytes: UInt64 = 0` property alongside `currentWatts`.

**Verification:** File compiles.

### Step 4: Integrate into ProcessMonitor.poll()

**File:** `Lowbeer/Core/ProcessMonitor.swift`

1. Add `let memoryLedger = MemoryLedger()` property
2. In `poll()`, pass `current.residentBytes` (from ProcessSnapshot) to each ProcessInfo
3. In the `DispatchQueue.main.async` block, call `memoryLedger.record()` for all processes (same pattern as energyLedger — all processes before truncation)
4. Call `memoryLedger.evictStale()` after recording

**Verification:** Build succeeds. All 84 tests pass.

### Step 5: Add MCP get_memory tool

**File:** `lowbeer-mcp/Sources/main.swift`

Add a `get_memory` tool that returns top processes by RAM (already have `residentBytes` from `pti_resident_size`). This is partially done — `get_processes` already returns `ram_mb`. Add a dedicated tool with anomaly detection:

```json
{
    "name": "get_memory",
    "description": "Get processes with highest memory usage. Flags anomalies: processes using >10 GB or growing >2x in 10 minutes.",
    "inputSchema": {
        "properties": {
            "limit": { "type": "integer", "default": 10 },
            "threshold_gb": { "type": "number", "default": 10 }
        }
    }
}
```

**Verification:** `swift build -c release` succeeds. Manual test with `echo '...' | lowbeer-mcp`.

### Step 6: Update Xcode project

**File:** `Lowbeer.xcodeproj/project.pbxproj`

Add MemoryLedger.swift to:
- PBXBuildFile section
- PBXFileReference section
- Core group children
- Sources build phase

**Verification:** `xcodebuild build` succeeds.

## Risks

| Risk | Mitigation |
|------|------------|
| ProcessSnapshot doesn't have residentBytes | It reads proc_taskinfo which has pti_resident_size — just needs to be exposed |
| Memory tracking adds overhead | Same O(n) per-process scan that already runs — just one more field |
| False positives on growth rate | 200-sample window (10 min) smooths transient spikes; 2x is a generous threshold |
