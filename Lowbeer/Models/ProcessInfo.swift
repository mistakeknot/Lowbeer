import AppKit
import Foundation

@Observable
final class ProcessInfo: Identifiable {
    let pid: pid_t
    let name: String
    let path: String
    let bundleIdentifier: String?
    let startTime: timeval
    var icon: NSImage?
    var cpuPercent: Double = 0
    var history: ProcessHistory = ProcessHistory()
    var isThrottled: Bool = false
    var throttleTarget: Double? = nil  // nil = full stop, 0.25 = 25% CPU
    var currentWatts: Double? = nil    // Per-process watts estimate from last poll
    var residentBytes: UInt64 = 0      // Resident memory from proc_taskinfo

    var id: pid_t { pid }

    init(pid: pid_t, name: String, path: String, bundleIdentifier: String? = nil,
         startTime: timeval = timeval(), icon: NSImage? = nil) {
        self.pid = pid
        self.name = name
        self.path = path
        self.bundleIdentifier = bundleIdentifier
        self.startTime = startTime
        self.icon = icon
    }

    var statusText: String {
        if !isThrottled { return "" }
        if let target = throttleTarget {
            return "\(Int(target * 100))% limit"
        }
        return "stopped"
    }
}
