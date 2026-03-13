import Foundation
import UserNotifications

/// Delivers macOS notifications when processes are throttled.
final class LowbeerNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = LowbeerNotificationManager()

    /// Called when user taps "Throttle" on an ask-first notification.
    var onThrottleApproved: ((pid_t) -> Void)?

    private static let askCategoryID = "ASK_THROTTLE"
    private static let drainCategoryID = "DRAIN_ALERT"
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
        let drainCategory = UNNotificationCategory(
            identifier: Self.drainCategoryID,
            actions: [throttleAction, ignoreAction],
            intentIdentifiers: []
        )
        // Must register ALL categories in one call — setNotificationCategories replaces the set
        center.setNotificationCategories([askCategory, drainCategory])
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

    /// Fire a notification for sustained high battery drain.
    func notifyDrain(
        systemWatts: Double,
        multiplier: Double,
        culpritName: String,
        culpritCPU: Double,
        culpritPID: pid_t
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Lowbeer — High Battery Drain"
        content.body = String(
            format: "Your Mac is using %.0fW (%.0fx normal). Top culprit: %@ at %d%% CPU.",
            systemWatts, multiplier, culpritName, Int(culpritCPU)
        )
        content.sound = .default
        content.categoryIdentifier = Self.drainCategoryID
        content.userInfo = ["pid": Int(culpritPID)]

        let request = UNNotificationRequest(
            identifier: "drain-alert",
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

    // Handle notification action responses (category-aware dispatch)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == Self.throttleActionID else { return }
        let category = response.notification.request.content.categoryIdentifier
        guard category == Self.askCategoryID || category == Self.drainCategoryID else { return }
        guard let pid = response.notification.request.content.userInfo["pid"] as? Int,
              pid > 0 else { return }
        await MainActor.run {
            onThrottleApproved?(pid_t(pid))
        }
    }
}
