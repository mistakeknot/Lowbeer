import Darwin
import Foundation

// libproc constants not bridged to Swift
private let PROC_PIDPATHINFO_SIZE: UInt32 = 4096

extension timeval: @retroactive Equatable {
    public static func == (lhs: timeval, rhs: timeval) -> Bool {
        lhs.tv_sec == rhs.tv_sec && lhs.tv_usec == rhs.tv_usec
    }
}

/// Raw per-process CPU time sample from proc_pidinfo.
struct ProcessSnapshot: Sendable {
    let pid: pid_t
    let name: String
    let path: String
    let totalUserNs: UInt64
    let totalSystemNs: UInt64
    let timestamp: CFAbsoluteTime
    let startTime: timeval

    var totalNs: UInt64 { totalUserNs + totalSystemNs }
}

/// Collects raw process snapshots using libproc.
enum ProcessSampler {
    /// Get process start time via sysctl. Returns nil if the process doesn't exist.
    static func getStartTime(for pid: pid_t) -> timeval? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let ret = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard ret == 0, size > 0 else { return nil }
        return info.kp_proc.p_starttime
    }

    /// Returns snapshots for all running processes.
    static func sampleAll() -> [pid_t: ProcessSnapshot] {
        let bufferSize = proc_listallpids(nil, 0)
        guard bufferSize > 0 else { return [:] }

        var pids = [pid_t](repeating: 0, count: Int(bufferSize))
        let actualCount = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))
        guard actualCount > 0 else { return [:] }

        let now = CFAbsoluteTimeGetCurrent()
        var results = [pid_t: ProcessSnapshot]()
        results.reserveCapacity(Int(actualCount))

        for i in 0..<Int(actualCount) {
            let pid = pids[i]
            guard pid > 0 else { continue }
            guard let startTime = getStartTime(for: pid) else { continue }

            var taskInfo = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
            guard ret == size else { continue }

            // Get process path
            var pathBuffer = [CChar](repeating: 0, count: Int(PROC_PIDPATHINFO_SIZE))
            let pathLen = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))

            let path: String
            let name: String
            if pathLen > 0 {
                path = String(cString: pathBuffer)
                name = (path as NSString).lastPathComponent
            } else {
                // Fall back to proc name
                var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN + 1))
                proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
                name = String(cString: nameBuffer)
                path = name
            }

            results[pid] = ProcessSnapshot(
                pid: pid,
                name: name,
                path: path,
                totalUserNs: taskInfo.pti_total_user,
                totalSystemNs: taskInfo.pti_total_system,
                timestamp: now,
                startTime: startTime
            )
        }
        return results
    }
}
