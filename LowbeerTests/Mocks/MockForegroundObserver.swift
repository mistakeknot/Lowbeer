import Foundation
@testable import Lowbeer

/// Mock foreground observer for testing ThrottleEngine.
final class MockForegroundObserver: ForegroundProviding {
    var foregroundPID: pid_t = 0
    var foregroundBundleID: String?
    var onForegroundChanged: ((pid_t, String?) -> Void)?

    func setForeground(pid: pid_t, bundleID: String? = nil) {
        foregroundPID = pid
        foregroundBundleID = bundleID
        onForegroundChanged?(pid, bundleID)
    }

    func isForeground(pid: pid_t) -> Bool {
        pid == foregroundPID
    }

    func isForeground(bundleID: String?) -> Bool {
        guard let bid = bundleID, let fgBid = foregroundBundleID else { return false }
        return bid == fgBid
    }
}
