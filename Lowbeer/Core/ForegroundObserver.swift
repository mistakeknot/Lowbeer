import AppKit
import Foundation

/// Watches for application activation to auto-resume throttled foreground apps.
@Observable
final class ForegroundObserver {
    private(set) var foregroundPID: pid_t = 0
    private(set) var foregroundBundleID: String?
    var onForegroundChanged: ((pid_t, String?) -> Void)?

    init() {
        if let front = NSWorkspace.shared.frontmostApplication {
            foregroundPID = front.processIdentifier
            foregroundBundleID = front.bundleIdentifier
        }
    }

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        foregroundPID = app.processIdentifier
        foregroundBundleID = app.bundleIdentifier
        onForegroundChanged?(foregroundPID, foregroundBundleID)
    }

    func isForeground(pid: pid_t) -> Bool {
        return pid == foregroundPID
    }

    func isForeground(bundleID: String?) -> Bool {
        guard let bid = bundleID, let fgBid = foregroundBundleID else { return false }
        return bid == fgBid
    }
}
