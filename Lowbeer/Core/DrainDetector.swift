import Foundation
import IOKit.ps

/// Ring buffer of system watts readings for computing a rolling average baseline.
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

/// Detect AC vs battery using IOPSCopyPowerSourcesInfo.
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

/// Detects sustained abnormal battery drain and fires a notification.
///
/// Called each poll cycle from ProcessMonitor. Compares current system power
/// against a rolling baseline and triggers a notification when drain exceeds
/// 2x normal for ~2 minutes while on battery.
///
/// **Threading:** All state is main-thread only (@MainActor).
@MainActor
final class DrainDetector {
    private var baseline = PowerBaseline()
    private var sustainedCount: Int = 0
    private var lastAlertTime: Date?
    private let multiplierThreshold: Double = 2.0
    private let sustainedCycles: Int = 40  // ~2 min at 3s intervals
    private let cooldownInterval: TimeInterval = 600  // 10 minutes

    /// Allow initialization from non-isolated contexts (e.g., ProcessMonitor property init).
    /// Safe because init only creates empty state.
    nonisolated init() {}

    func evaluate(
        systemWatts: Double,
        topProcess: ProcessInfo?,
        notificationsEnabled: Bool
    ) {
        let onBattery = BatteryState.isOnBattery

        // Feed baseline only when:
        // 1. Not in a detected drain state (prevents baseline contamination)
        // 2. On battery (prevents AC-power readings from polluting battery baseline)
        // Exception: always feed during warmup so cold-start drain doesn't stall the baseline.
        if !baseline.isWarmed || (sustainedCount == 0 && onBattery) {
            baseline.append(systemWatts)
        }

        guard notificationsEnabled,
              baseline.isWarmed,
              onBattery
        else {
            sustainedCount = 0
            return
        }

        let avg = baseline.average
        guard avg > 1.0, systemWatts > avg * multiplierThreshold else {
            // Grace window: decrement instead of hard-resetting to 0.
            // A single sub-threshold cycle during a 2-minute sustained spike
            // shouldn't reset the entire detector.
            if sustainedCount > 0 {
                sustainedCount -= 1
            }
            return
        }

        sustainedCount += 1
        guard sustainedCount >= sustainedCycles else { return }

        // Cooldown check
        if let last = lastAlertTime,
           Date().timeIntervalSince(last) < cooldownInterval {
            return
        }

        // Fire notification — use topProcess consistently for culprit identity
        guard let culprit = topProcess, culprit.pid != 0 else { return }

        let multiplier = systemWatts / avg
        LowbeerNotificationManager.shared.notifyDrain(
            systemWatts: systemWatts,
            multiplier: multiplier,
            culpritName: culprit.name,
            culpritCPU: culprit.cpuPercent,
            culpritPID: culprit.pid
        )

        lastAlertTime = Date()
        sustainedCount = 0  // Reset after firing
    }
}
