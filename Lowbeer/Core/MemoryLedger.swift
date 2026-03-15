import AppKit
import Foundation

/// Per-process memory tracking with anomaly detection.
struct MemoryEntry {
    let identity: String
    var displayName: String
    var currentBytes: UInt64 = 0
    var peakBytes: UInt64 = 0
    var lastSeen: Date = Date()
    var icon: NSImage?

    // Ring buffer for growth-rate detection
    private(set) var history: [UInt64]
    private var historyIndex: Int = 0
    private(set) var historyCount: Int = 0

    static let historyCapacity = 200  // ~10 min at 3s intervals

    init(identity: String, displayName: String) {
        self.identity = identity
        self.displayName = displayName
        self.history = Array(repeating: 0, count: Self.historyCapacity)
    }

    mutating func appendHistory(_ bytes: UInt64) {
        history[historyIndex] = bytes
        historyIndex = (historyIndex + 1) % Self.historyCapacity
        if historyCount < Self.historyCapacity { historyCount += 1 }
    }

    /// Oldest reading still in the ring buffer.
    var oldestReading: UInt64? {
        guard historyCount > 0 else { return nil }
        if historyCount < Self.historyCapacity {
            return history[0]
        }
        return history[historyIndex]  // Oldest slot after wrap
    }

    var currentMB: Double { Double(currentBytes) / (1024 * 1024) }
    var currentGB: Double { Double(currentBytes) / (1024 * 1024 * 1024) }
    var peakMB: Double { Double(peakBytes) / (1024 * 1024) }
}

/// Tracks per-process resident memory and detects anomalous growth.
///
/// Called each poll cycle from ProcessMonitor. Records current resident bytes
/// per app identity and maintains a ring buffer for growth-rate detection.
///
/// **Threading:** All state is main-thread only (@MainActor).
@MainActor
@Observable
final class MemoryLedger {
    private(set) var entries: [String: MemoryEntry] = [:]

    /// Processes absent for more than 1 hour are evicted.
    let evictionWindow: TimeInterval = 3600

    /// Absolute threshold — any process exceeding this is anomalous.
    static let absoluteThreshold: UInt64 = 10 * 1024 * 1024 * 1024  // 10 GB

    /// Growth multiplier — 2x growth within the history window is anomalous.
    static let growthMultiplier: Double = 2.0

    /// Minimum history samples before growth detection activates.
    static let minHistoryForGrowth: Int = 100  // ~5 min

    nonisolated init() {}

    func record(identity: String, displayName: String,
                residentBytes: UInt64, icon: NSImage?) {
        var entry = entries[identity] ?? MemoryEntry(identity: identity, displayName: displayName)
        entry.currentBytes = residentBytes
        entry.peakBytes = max(entry.peakBytes, residentBytes)
        entry.lastSeen = Date()
        entry.displayName = displayName
        entry.appendHistory(residentBytes)
        if entry.icon == nil { entry.icon = icon }
        entries[identity] = entry
    }

    func evictStale() {
        let cutoff = Date().addingTimeInterval(-evictionWindow)
        entries = entries.filter { $0.value.lastSeen > cutoff }
    }

    /// Entries sorted by current resident bytes descending.
    var topConsumers: [MemoryEntry] {
        entries.values.sorted { $0.currentBytes > $1.currentBytes }
    }

    /// Entries that exceed the absolute threshold or show rapid growth.
    var anomalies: [MemoryEntry] {
        entries.values.filter { entry in
            // Absolute threshold check
            if entry.currentBytes > Self.absoluteThreshold { return true }

            // Growth rate check — need enough history
            guard entry.historyCount >= Self.minHistoryForGrowth,
                  let oldest = entry.oldestReading,
                  oldest > 0
            else { return false }

            let growth = Double(entry.currentBytes) / Double(oldest)
            return growth >= Self.growthMultiplier
        }.sorted { $0.currentBytes > $1.currentBytes }
    }
}
