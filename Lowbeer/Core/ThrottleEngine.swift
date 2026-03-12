import AppKit
import Foundation

/// Evaluates processes against rules and applies SIGSTOP/SIGCONT throttling.
@Observable
final class ThrottleEngine {
    private let monitor: ProcessMonitor
    private let foreground: ForegroundProviding
    let settings: LowbeerSettings

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

    init(monitor: ProcessMonitor, foreground: ForegroundProviding, settings: LowbeerSettings = .shared) {
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

    // MARK: - Session Lifecycle

    /// Deactivate a throttle session and clean up all associated state.
    private func releaseSession(pid: pid_t, resetExceedCount: Bool = true) {
        guard let session = sessions[pid] else { return }
        session.deactivate()
        sessions.removeValue(forKey: pid)
        if resetExceedCount {
            exceedCounts[pid] = 0
        }
        if let process = monitor.processes.first(where: { $0.pid == pid }) {
            process.isThrottled = false
            process.throttleTarget = nil
        }
    }

    // MARK: - Rule Matching

    /// Find the first matching enabled rule for a process, or nil for global threshold.
    private func matchingRule(for process: ProcessInfo) -> ThrottleRule? {
        settings.rules.first { rule in
            rule.enabled && rule.identity.matches(bundleID: process.bundleIdentifier, path: process.path)
        }
    }

    // MARK: - Evaluation

    /// Called each poll cycle to evaluate all processes.
    func evaluate() {
        guard !settings.isPaused else { return }

        let activePIDs = Set(monitor.processes.map(\.pid))

        // Clean up sessions for processes that no longer exist
        for (pid, session) in sessions where !activePIDs.contains(pid) {
            session.deactivate()
            sessions.removeValue(forKey: pid)
        }

        // Detect PID reuse: deactivate sessions whose startTime no longer matches
        for process in monitor.processes {
            if let session = sessions[process.pid],
               session.startTime != process.startTime {
                releaseSession(pid: process.pid)
            }
        }

        // Evaluate each process
        for process in monitor.processes {
            let isFg = foreground.isForeground(pid: process.pid)
                || foreground.isForeground(bundleID: process.bundleIdentifier)

            // If foreground and currently throttled, auto-resume
            if isFg, sessions[process.pid] != nil {
                releaseSession(pid: process.pid)
                continue
            }

            // Find matching rule once (used for threshold, action, and session)
            let matchedRule = matchingRule(for: process)
            let threshold = matchedRule?.cpuThreshold ?? settings.globalCPUThreshold

            // Track how long this process has exceeded threshold
            if process.cpuPercent > threshold {
                exceedCounts[process.pid, default: 0] += 1
            } else {
                exceedCounts[process.pid] = 0
                promptedPIDs.remove(process.pid)

                // If process dropped below threshold and is throttled, release it
                if sessions[process.pid] != nil {
                    releaseSession(pid: process.pid, resetExceedCount: false)
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

            // Apply throttle
            let session = ThrottleSession(
                pid: process.pid,
                processName: process.name,
                startTime: process.startTime,
                rule: matchedRule,
                action: action
            )
            sessions[process.pid] = session

            if case .notifyOnly = action {
                // notifyOnly: keep session for dedup (prevents re-notification
                // every poll cycle) but don't send SIGSTOP
                if settings.notificationsEnabled {
                    LowbeerNotificationManager.shared.notifyThrottled(
                        processName: process.name,
                        pid: process.pid,
                        action: action
                    )
                }
            } else {
                session.activate()

                // Update process model
                process.isThrottled = true
                if case .throttleTo(let target) = action {
                    process.throttleTarget = target
                } else if case .stop = action {
                    process.throttleTarget = nil
                }

                if settings.notificationsEnabled {
                    LowbeerNotificationManager.shared.notifyThrottled(
                        processName: process.name,
                        pid: process.pid,
                        action: action
                    )
                }
            }
        }
    }

    /// Manually resume a specific process.
    func resume(pid: pid_t) {
        releaseSession(pid: pid)
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
        for (_, session) in sessions {
            session.deactivate()
        }
        for process in monitor.processes where process.isThrottled {
            process.isThrottled = false
            process.throttleTarget = nil
        }
        sessions.removeAll()
        exceedCounts.removeAll()
        promptedPIDs.removeAll()
    }

    private func handleForegroundChange(pid: pid_t) {
        releaseSession(pid: pid)
    }
}
