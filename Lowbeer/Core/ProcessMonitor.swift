import AppKit
import Combine
import Foundation

/// Polls all processes at a configurable interval and computes CPU % from deltas.
@Observable
final class ProcessMonitor {
    private(set) var processes: [ProcessInfo] = []
    private(set) var totalCPU: Double = 0
    private(set) var latestPower: PowerSample = .zero
    let powerSampler = PowerSampler()
    let energyLedger = EnergyLedger()
    let memoryLedger = MemoryLedger()
    let drainDetector = DrainDetector()

    /// For testing: inject processes directly. Accessible via @testable import.
    func setProcessesForTesting(_ processes: [ProcessInfo]) {
        self.processes = processes
        self.totalCPU = processes.reduce(0) { $0 + $1.cpuPercent }
    }

    private var timer: Timer?
    private var previousSamples: [pid_t: ProcessSnapshot] = [:]
    private var processCache: [pid_t: ProcessInfo] = [:]
    private let processorCount = Double(ProcessInfo_Helpers.activeProcessorCount)

    var pollInterval: TimeInterval {
        didSet {
            guard pollInterval != oldValue else { return }
            startPolling()
        }
    }

    init(pollInterval: TimeInterval = 3) {
        self.pollInterval = pollInterval
    }

    func start() {
        // Take initial baseline sample
        previousSamples = ProcessSampler.sampleAll()
        startPolling()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let currentSamples = ProcessSampler.sampleAll()
        let prev = previousSamples
        previousSamples = currentSamples

        guard !prev.isEmpty else { return }

        // Build icon/bundle lookup from NSRunningApplication
        let runningApps = NSWorkspace.shared.runningApplications
        var appsByPID = [pid_t: NSRunningApplication]()
        for app in runningApps {
            appsByPID[app.processIdentifier] = app
        }

        var updated = [ProcessInfo]()
        var total: Double = 0

        for (pid, current) in currentSamples {
            guard let previous = prev[pid] else { continue }

            let deltaNs = current.totalNs - previous.totalNs
            let deltaTime = current.timestamp - previous.timestamp
            guard deltaTime > 0 else { continue }

            // CPU % relative to one core, then divide by number of cores for system-wide %
            // Actually, display per-core percentage (like Activity Monitor shows)
            let cpuPercent = (Double(deltaNs) / (deltaTime * 1_000_000_000)) * 100.0

            guard cpuPercent >= 0.1 else { continue }  // Filter idle processes

            let info: ProcessInfo
            if let cached = processCache[pid],
               cached.name == current.name,
               cached.startTime == current.startTime {
                info = cached
            } else {
                let app = appsByPID[pid]
                info = ProcessInfo(
                    pid: pid,
                    name: app?.localizedName ?? current.name,
                    path: current.path,
                    bundleIdentifier: app?.bundleIdentifier,
                    startTime: current.startTime,
                    icon: app?.icon
                )
                processCache[pid] = info
            }

            info.cpuPercent = cpuPercent
            info.residentBytes = current.residentBytes
            info.history.append(cpuPercent)
            total += cpuPercent
            updated.append(info)
        }

        // Clean stale cache entries
        let activePIDs = Set(currentSamples.keys)
        processCache = processCache.filter { activePIDs.contains($0.key) }

        // Sort by CPU descending
        updated.sort { $0.cpuPercent > $1.cpuPercent }

        let power = powerSampler.sample()

        // Compute actual elapsed time from sample timestamps (not pollInterval)
        // to handle timer coalescing, load delays, and interval changes correctly.
        let elapsed: TimeInterval = {
            if let anyPrev = prev.values.first,
               let anyCurr = currentSamples[anyPrev.pid] ?? currentSamples.values.first {
                let dt = anyCurr.timestamp - anyPrev.timestamp
                return dt > 0 ? dt : pollInterval
            }
            return pollInterval
        }()

        // Energy accumulation: run on ALL processes before truncating to top 50.
        // This ensures processes ranked 51+ still get their energy attributed.
        let systemWatts = min(power.totalWatts, EnergyLedger.maxPlausibleWatts)
        let allProcesses = updated  // Keep reference to full list for energy
        let displayProcesses = updated.count > 50 ? Array(updated.prefix(50)) : updated

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.processes = displayProcesses
            self.totalCPU = total
            self.latestPower = power

            // Accumulate per-process energy on main thread (EnergyLedger is @MainActor)
            if systemWatts >= 1.0, total >= 1.0 {
                for process in allProcesses {
                    let share = process.cpuPercent / total
                    let processWatts = share * systemWatts
                    let whIncrement = processWatts * (elapsed / 3600.0)
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
            } else {
                // Below threshold — clear instantaneous watts to avoid stale values
                for process in allProcesses {
                    process.currentWatts = nil
                }
            }

            // Memory tracking — record for all processes before truncation
            for process in allProcesses {
                self.memoryLedger.record(
                    identity: process.bundleIdentifier ?? process.path,
                    displayName: process.name,
                    residentBytes: process.residentBytes,
                    icon: process.icon
                )
            }
            self.memoryLedger.evictStale()

            // Drain detection — always runs (baseline needs continuous feeding).
            // Uses clamped systemWatts to prevent false wake-from-sleep alerts.
            self.drainDetector.evaluate(
                systemWatts: systemWatts,
                topProcess: displayProcesses.first,
                notificationsEnabled: LowbeerSettings.shared.notificationsEnabled
            )
        }
    }
}

enum ProcessInfo_Helpers {
    static var activeProcessorCount: Int {
        Foundation.ProcessInfo.processInfo.activeProcessorCount
    }
}
