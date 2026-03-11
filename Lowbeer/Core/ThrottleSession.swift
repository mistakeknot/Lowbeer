import Foundation
import os.log

private let logger = Logger(subsystem: "com.lowbeer", category: "throttle")

/// Tracks the state of throttling for a single process.
final class ThrottleSession {
    let pid: pid_t
    let processName: String
    let startTime: timeval
    let rule: ThrottleRule?
    let action: ThrottleAction

    private(set) var isStopped: Bool = false
    private(set) var startedAt: Date = Date()
    private var dutyCycleTimer: Timer?

    init(pid: pid_t, processName: String, startTime: timeval,
         rule: ThrottleRule?, action: ThrottleAction) {
        self.pid = pid
        self.processName = processName
        self.startTime = startTime
        self.rule = rule
        self.action = action
    }

    deinit {
        deactivate()
    }

    /// Begin throttling this process.
    func activate() {
        switch action {
        case .stop:
            sendStop()
        case .throttleTo(let fraction):
            startDutyCycle(fraction: fraction)
        case .notifyOnly:
            break  // Handled externally
        }
    }

    /// Resume the process and stop any duty-cycle timer.
    func deactivate() {
        dutyCycleTimer?.invalidate()
        dutyCycleTimer = nil
        if isStopped {
            sendCont()
        }
    }

    private func sendStop() {
        guard verifyProcess() else { return }
        let result = kill(pid, SIGSTOP)
        guard result == 0 else { return }
        isStopped = true
        // Post-signal re-verify: if PID was reused between verify and kill, undo immediately
        if !verifyProcess() {
            sendCont()
        }
    }

    private func sendCont() {
        kill(pid, SIGCONT)
        isStopped = false
    }

    /// Duty-cycle throttling: run for `fraction` of each 1-second period.
    private func startDutyCycle(fraction: Double) {
        let period: TimeInterval = 1.0
        let runTime = period * max(0.05, min(0.95, fraction))

        sendStop()

        // Alternate between SIGCONT (run) and SIGSTOP (stop)
        dutyCycleTimer = Timer.scheduledTimer(withTimeInterval: period, repeats: true) { [weak self] _ in
            guard let self, self.verifyProcess() else {
                self?.deactivate()
                return
            }
            // CONT for runTime, then STOP
            self.sendCont()
            DispatchQueue.main.asyncAfter(deadline: .now() + runTime) { [weak self] in
                guard let self, self.dutyCycleTimer != nil else { return }
                self.sendStop()
            }
        }
    }

    /// Verify PID still belongs to the expected process via start-time comparison.
    /// Fail-closed: returns false if sysctl fails or start time differs.
    private func verifyProcess() -> Bool {
        guard let currentStartTime = ProcessSampler.getStartTime(for: pid) else {
            logger.info("PID \(self.pid) no longer exists — deactivating throttle")
            return false
        }
        guard currentStartTime == startTime else {
            logger.warning("PID \(self.pid) reused: expected start \(self.startTime.tv_sec), got \(currentStartTime.tv_sec) — deactivating")
            return false
        }
        return true
    }

    var elapsedDescription: String {
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }
}
