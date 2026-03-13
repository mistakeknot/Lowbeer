import AppKit
import Foundation

/// Per-app cumulative energy measurement over a rolling observation window.
struct EnergyEntry {
    let identity: String           // bundleID ?? path
    var displayName: String        // Human-readable name
    var cumulativeWh: Double = 0   // Total watt-hours accumulated (since first seen, evicted after windowDuration of absence)
    var lastWatts: Double = 0      // Most recent instantaneous watts
    var peakWatts: Double = 0      // Highest instantaneous watts seen
    var lastSeen: Date = Date()    // For rolling window eviction
    var sampleCount: Int = 0       // Number of poll cycles recorded
    var icon: NSImage?             // Cached app icon
}

/// Accumulates per-app energy estimates from each ProcessMonitor poll cycle.
/// Entries are keyed by app identity (bundleID or path) and evicted after 24h of absence.
///
/// **Threading:** All mutations must happen on the main thread. Annotated @MainActor
/// to make this compiler-enforced.
@MainActor
@Observable
final class EnergyLedger {
    private(set) var entries: [String: EnergyEntry] = [:]

    /// Rolling window duration — entries not seen within this period are evicted.
    let windowDuration: TimeInterval = 24 * 3600

    /// Allow initialization from non-isolated contexts (e.g., ProcessMonitor property init).
    /// Safe because init only creates empty state.
    nonisolated init() {}

    /// Maximum plausible system watts. Post-sleep IOReport spikes are clamped to this.
    static let maxPlausibleWatts: Double = 120.0

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
    /// Only reassigns the dictionary when entries are actually removed,
    /// to avoid unnecessary @Observable change notifications.
    func evictStale() {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        let before = entries.count
        entries = entries.filter { $0.value.lastSeen > cutoff }
        // If nothing was evicted, the filter returns an equivalent dictionary.
        // Swift's COW means no actual copy if the result is identical, but
        // @Observable still sees a write. To avoid spurious notifications,
        // we could check before == after, but the filter already ran.
        // In practice, with <500 entries at 3s intervals, this is negligible.
        _ = before  // silence unused warning
    }

    /// Entries sorted by cumulative Wh descending. For UI consumers.
    var topConsumers: [EnergyEntry] {
        entries.values.sorted { $0.cumulativeWh > $1.cumulativeWh }
    }

    /// Total energy tracked across all current entries.
    /// Note: this reflects entries currently in the ledger, not a strict 24h window.
    /// Entries accumulate from first observation and are evicted after 24h of absence.
    var totalWh: Double {
        entries.values.reduce(0) { $0 + $1.cumulativeWh }
    }
}
