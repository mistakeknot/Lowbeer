import Foundation
import UserNotifications

/// Delivers macOS notifications when processes are throttled.
final class LowbeerNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LowbeerNotificationManager()

    /// Called when user taps "Throttle" on an ask-first notification.
    var onThrottleApproved: ((pid_t) -> Void)?

    private static let askCategoryID = "ASK_THROTTLE"
    private static let throttleActionID = "THROTTLE_ACTION"
    private static let ignoreActionID = "IGNORE_ACTION"

    private override init() {
        super.init()
    }

    func setup() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification auth error: \(error)")
            }
        }

        // Register actionable category for ask-first mode
        let throttleAction = UNNotificationAction(
            identifier: Self.throttleActionID,
            title: "Throttle",
            options: []
        )
        let ignoreAction = UNNotificationAction(
            identifier: Self.ignoreActionID,
            title: "Ignore",
            options: []
        )
        let askCategory = UNNotificationCategory(
            identifier: Self.askCategoryID,
            actions: [throttleAction, ignoreAction],
            intentIdentifiers: []
        )
        center.setNotificationCategories([askCategory])
    }

    func notifyThrottled(processName: String, pid: pid_t, action: ThrottleAction) {
        let content = UNMutableNotificationContent()
        content.title = "Lowbeer"

        switch action {
        case .stop:
            content.body = "\(processName) (PID \(pid)) has been stopped due to high CPU usage."
        case .throttleTo(let target):
            content.body = "\(processName) (PID \(pid)) throttled to \(Int(target * 100))% CPU."
        case .notifyOnly:
            content.body = "\(processName) (PID \(pid)) is using excessive CPU."
        }

        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "throttle-\(pid)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// Send a notification asking the user whether to throttle a process.
    func askToThrottle(processName: String, pid: pid_t, cpuPercent: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Lowbeer — High CPU"
        content.body = "\(processName) is using \(Int(cpuPercent))% CPU. Throttle it?"
        content.sound = .default
        content.categoryIdentifier = Self.askCategoryID
        content.userInfo = ["pid": Int(pid)]

        let request = UNNotificationRequest(
            identifier: "ask-\(pid)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // Show notifications even when app is frontmost
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // Handle notification action responses
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.throttleActionID else { return }
        guard let pid = response.notification.request.content.userInfo["pid"] as? Int else { return }
        await MainActor.run {
            onThrottleApproved?(pid_t(pid))
        }
    }
}
