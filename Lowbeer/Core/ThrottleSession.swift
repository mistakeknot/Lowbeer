import Foundation

/// Tracks the state of throttling for a single process.
final class ThrottleSession {
    let pid: pid_t
    let processName: String
    let rule: ThrottleRule?
    let action: ThrottleAction

    private(set) var isStopped: Bool = false
    private(set) var startedAt: Date = Date()
    private var dutyCycleTimer: Timer?

    init(pid: pid_t, processName: String, rule: ThrottleRule?, action: ThrottleAction) {
        self.pid = pid
        self.processName = processName
        self.rule = rule
        self.action = action
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
        // Verify PID still belongs to expected process before stopping
        guard verifyProcess() else { return }
        kill(pid, SIGSTOP)
        isStopped = true
    }

    private func sendCont() {
        kill(pid, SIGCONT)
        isStopped = false
    }

    /// Duty-cycle throttling: run for `fraction` of each 1-second period.
    private func startDutyCycle(fraction: Double) {
        let period: TimeInterval = 1.0
        let runTime = period * max(0.05, min(0.95, fraction))
        let stopTime = period - runTime

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

    /// Verify PID still belongs to the expected process (PIDs can be reused).
    private func verifyProcess() -> Bool {
        var nameBuffer = [CChar](repeating: 0, count: Int(MAXCOMLEN + 1))
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let currentName = String(cString: nameBuffer)
        return currentName == processName || processName.hasPrefix(currentName)
    }

    var elapsedDescription: String {
        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < 60 { return "\(Int(elapsed))s ago" }
        if elapsed < 3600 { return "\(Int(elapsed / 60))m ago" }
        return "\(Int(elapsed / 3600))h ago"
    }
}
