import AppKit
import Combine
import Foundation

/// Polls all processes at a configurable interval and computes CPU % from deltas.
@Observable
final class ProcessMonitor {
    private(set) var processes: [ProcessInfo] = []
    private(set) var totalCPU: Double = 0

    private var timer: Timer?
    private var previousSamples: [pid_t: ProcessSnapshot] = [:]
    private var processCache: [pid_t: ProcessInfo] = [:]
    private let processorCount = Double(ProcessInfo_Helpers.activeProcessorCount)
    private let queue = DispatchQueue(label: "com.lowbeer.monitor", qos: .utility)

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
            if let cached = processCache[pid], cached.name == current.name {
                info = cached
            } else {
                let app = appsByPID[pid]
                info = ProcessInfo(
                    pid: pid,
                    name: app?.localizedName ?? current.name,
                    path: current.path,
                    bundleIdentifier: app?.bundleIdentifier,
                    icon: app?.icon
                )
                processCache[pid] = info
            }

            info.cpuPercent = cpuPercent
            info.history.append(cpuPercent)
            total += cpuPercent
            updated.append(info)
        }

        // Clean stale cache entries
        let activePIDs = Set(currentSamples.keys)
        processCache = processCache.filter { activePIDs.contains($0.key) }

        // Sort by CPU descending, keep top 50
        updated.sort { $0.cpuPercent > $1.cpuPercent }
        if updated.count > 50 { updated = Array(updated.prefix(50)) }

        DispatchQueue.main.async { [weak self] in
            self?.processes = updated
            self?.totalCPU = total
        }
    }
}

enum ProcessInfo_Helpers {
    static var activeProcessorCount: Int {
        Foundation.ProcessInfo.processInfo.activeProcessorCount
    }
}
