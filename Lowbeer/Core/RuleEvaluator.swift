import Foundation

/// Matches processes against configured throttle rules and the global threshold.
enum RuleEvaluator {
    /// Returns the action to take for a process, if any.
    /// Returns nil if the process should not be throttled.
    static func evaluate(
        process: ProcessInfo,
        consecutiveExceedCount: Int,
        settings: LowbeerSettings,
        isForeground: Bool
    ) -> ThrottleAction? {
        // Check safety list first
        if SafetyList.isProtected(name: process.name, path: process.path, pid: process.pid) {
            return nil
        }

        // Check per-app rules
        for rule in settings.rules where rule.enabled {
            if rule.identity.matches(bundleID: process.bundleIdentifier, path: process.path) {
                // Check schedule
                if let schedule = rule.schedule, !ScheduleEvaluator.isActive(schedule) {
                    continue
                }

                // Check foreground
                if rule.throttleInBackground && isForeground {
                    return nil
                }

                // Check threshold and sustained duration
                let samplesNeeded = max(1, rule.sustainedSeconds / Int(settings.pollInterval))
                if process.cpuPercent > rule.cpuThreshold && consecutiveExceedCount >= samplesNeeded {
                    return rule.action
                }

                // Rule matched but threshold not met — don't fall through to global
                return nil
            }
        }

        // Global threshold
        let globalSamplesNeeded = max(1, settings.sustainedSeconds / Int(settings.pollInterval))
        if process.cpuPercent > settings.globalCPUThreshold && consecutiveExceedCount >= globalSamplesNeeded {
            return settings.defaultAction
        }

        return nil
    }
}
