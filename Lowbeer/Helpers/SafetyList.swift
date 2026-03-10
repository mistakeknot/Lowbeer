import Foundation

/// Processes that must never be throttled. Stopping these can crash the system.
enum SafetyList {
    /// Process names that are always protected.
    static let protectedNames: Set<String> = [
        "kernel_task", "launchd", "WindowServer", "loginwindow",
        "Finder", "Dock", "SystemUIServer", "coreaudiod", "audiod",
        "coreduetd", "powerd", "diskarbitrationd", "notifyd",
        "opendirectoryd", "securityd", "trustd", "configd",
        "mds", "mds_stores", "distnoted", "UserEventAgent",
        "Lowbeer"  // Never throttle ourselves
    ]

    /// Path prefixes that are always protected.
    static let protectedPathPrefixes: [String] = [
        "/System/",
        "/usr/libexec/",
        "/usr/sbin/",
    ]

    /// Returns true if the process should never be throttled.
    static func isProtected(name: String, path: String, pid: pid_t) -> Bool {
        // Our own PID
        if pid == Foundation.ProcessInfo.processInfo.processIdentifier { return true }

        // PID 0 (kernel) and PID 1 (launchd)
        if pid <= 1 { return true }

        // Protected names
        if protectedNames.contains(name) { return true }

        // Protected paths
        for prefix in protectedPathPrefixes {
            if path.hasPrefix(prefix) { return true }
        }

        // User-configured allowlist
        let userAllowlist = LowbeerSettings.shared.userAllowlist
        for identity in userAllowlist {
            if identity.matches(bundleID: nil, path: path) { return true }
            if identity.displayName == name { return true }
        }

        return false
    }
}
