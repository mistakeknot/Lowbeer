import AppKit
import Foundation

/// Evaluates processes against rules and applies SIGSTOP/SIGCONT throttling.
@Observable
final class ThrottleEngine {
    private let monitor: ProcessMonitor
    private let foreground: ForegroundObserver
    private let settings: LowbeerSettings

    /// Active throttle sessions keyed by PID.
    private(set) var sessions: [pid_t: ThrottleSession] = [:]

    /// Consecutive samples each process has exceeded its threshold.
    private var exceedCounts: [pid_t: Int] = [:]

    /// PIDs that have been prompted in ask-first mode (to avoid repeated notifications).
    private var promptedPIDs: Set<pid_t> = []

    var throttledProcesses: [ThrottleSession] {
        Array(sessions.values).sorted { $0.startedAt < $1.startedAt }
    }

    var throttledCount: Int { sessions.count }

    init(monitor: ProcessMonitor, foreground: ForegroundObserver, settings: LowbeerSettings = .shared) {
        self.monitor = monitor
        self.foreground = foreground
        self.settings = settings

        // Auto-resume when a throttled app becomes foreground
        foreground.onForegroundChanged = { [weak self] pid, _ in
            self?.handleForegroundChange(pid: pid)
        }

        // Handle ask-first notification approval
        LowbeerNotificationManager.shared.onThrottleApproved = { [weak self] pid in
            self?.throttle(pid: pid)
        }
    }

    /// Called each poll cycle to evaluate all processes.
    func evaluate() {
        guard !settings.isPaused else { return }

        let activePIDs = Set(monitor.processes.map(\.pid))

        // Clean up sessions for processes that no longer exist
        for (pid, session) in sessions {
            if !activePIDs.contains(pid) {
                session.deactivate()
                sessions.removeValue(forKey: pid)
            }
        }

        // Detect PID reuse: deactivate sessions whose startTime no longer matches
        for process in monitor.processes {
            if let session = sessions[process.pid],
               session.startTime != process.startTime {
                session.deactivate()
                sessions.removeValue(forKey: process.pid)
                process.isThrottled = false
                process.throttleTarget = nil
                exceedCounts[process.pid] = 0
            }
        }

        // Evaluate each process
        for process in monitor.processes {
            let isFg = foreground.isForeground(pid: process.pid)
                || foreground.isForeground(bundleID: process.bundleIdentifier)

            // If foreground and currently throttled, auto-resume
            if isFg, let session = sessions[process.pid] {
                session.deactivate()
                sessions.removeValue(forKey: process.pid)
                process.isThrottled = false
                process.throttleTarget = nil
                exceedCounts[process.pid] = 0
                continue
            }

            // Track how long this process has exceeded threshold
            let threshold = matchingThreshold(for: process)
            if process.cpuPercent > threshold {
                exceedCounts[process.pid, default: 0] += 1
            } else {
                exceedCounts[process.pid] = 0
                promptedPIDs.remove(process.pid)

                // If process dropped below threshold and is throttled, release it
                if let session = sessions[process.pid] {
                    session.deactivate()
                    sessions.removeValue(forKey: process.pid)
                    process.isThrottled = false
                    process.throttleTarget = nil
                }
            }

            // Skip if already throttled
            if sessions[process.pid] != nil { continue }

            // Evaluate rules
            let count = exceedCounts[process.pid] ?? 0
            guard let action = RuleEvaluator.evaluate(
                process: process,
                consecutiveExceedCount: count,
                settings: settings,
                isForeground: isFg
            ) else { continue }

            // In ask-first mode, prompt the user instead of throttling immediately
            if settings.throttleMode == .askFirst {
                if !promptedPIDs.contains(process.pid) {
                    promptedPIDs.insert(process.pid)
                    LowbeerNotificationManager.shared.askToThrottle(
                        processName: process.name,
                        pid: process.pid,
                        cpuPercent: process.cpuPercent
                    )
                }
                continue
            }

            // Find matching rule for the session
            let matchedRule = settings.rules.first { rule in
                rule.enabled && rule.identity.matches(bundleID: process.bundleIdentifier, path: process.path)
            }

            // Apply throttle
            let session = ThrottleSession(
                pid: process.pid,
                processName: process.name,
                startTime: process.startTime,
                rule: matchedRule,
                action: action
            )
            sessions[process.pid] = session
            session.activate()

            // Update process model
            process.isThrottled = true
            if case .throttleTo(let target) = action {
                process.throttleTarget = target
            } else if case .stop = action {
                process.throttleTarget = nil
            }

            // Notify
            if settings.notificationsEnabled, case .notifyOnly = action {
                // notifyOnly doesn't throttle, just alerts
            } else if settings.notificationsEnabled {
                LowbeerNotificationManager.shared.notifyThrottled(
                    processName: process.name,
                    pid: process.pid,
                    action: action
                )
            }

            if case .notifyOnly = action {
                // Don't actually track as a session for notify-only
                sessions.removeValue(forKey: process.pid)
                LowbeerNotificationManager.shared.notifyThrottled(
                    processName: process.name,
                    pid: process.pid,
                    action: action
                )
            }
        }
    }

    /// Manually resume a specific process.
    func resume(pid: pid_t) {
        guard let session = sessions[pid] else { return }
        session.deactivate()
        sessions.removeValue(forKey: pid)
        exceedCounts[pid] = 0

        if let process = monitor.processes.first(where: { $0.pid == pid }) {
            process.isThrottled = false
            process.throttleTarget = nil
        }
    }

    /// Manually throttle a specific process.
    func throttle(pid: pid_t, action: ThrottleAction = .stop) {
        guard sessions[pid] == nil else { return }
        guard let process = monitor.processes.first(where: { $0.pid == pid }) else { return }
        guard !SafetyList.isProtected(name: process.name, path: process.path, pid: pid) else { return }

        let session = ThrottleSession(pid: pid, processName: process.name, startTime: process.startTime, rule: nil, action: action)
        sessions[pid] = session
        session.activate()
        process.isThrottled = true
        if case .throttleTo(let target) = action {
            process.throttleTarget = target
        }
    }

    /// Resume all throttled processes.
    func resumeAll() {
        for (pid, session) in sessions {
            session.deactivate()
            if let process = monitor.processes.first(where: { $0.pid == pid }) {
                process.isThrottled = false
                process.throttleTarget = nil
            }
        }
        sessions.removeAll()
        exceedCounts.removeAll()
        promptedPIDs.removeAll()
    }

    private func handleForegroundChange(pid: pid_t) {
        if let session = sessions[pid] {
            session.deactivate()
            sessions.removeValue(forKey: pid)
            exceedCounts[pid] = 0

            if let process = monitor.processes.first(where: { $0.pid == pid }) {
                process.isThrottled = false
                process.throttleTarget = nil
            }
        }
    }

    private func matchingThreshold(for process: ProcessInfo) -> Double {
        for rule in settings.rules where rule.enabled {
            if rule.identity.matches(bundleID: process.bundleIdentifier, path: process.path) {
                return rule.cpuThreshold
            }
        }
        return settings.globalCPUThreshold
    }
}
