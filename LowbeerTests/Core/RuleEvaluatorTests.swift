import XCTest
@testable import Lowbeer

final class RuleEvaluatorTests: XCTestCase {

    private func makeSettings() -> LowbeerSettings {
        let s = LowbeerSettings(forTesting: true)
        s.globalCPUThreshold = 80
        s.sustainedSeconds = 30
        s.pollInterval = 3
        s.defaultAction = .stop
        return s
    }

    private func makeProcess(
        name: String = "TestApp",
        path: String = "/Applications/TestApp.app/Contents/MacOS/TestApp",
        pid: pid_t = 500,
        bundleID: String? = "com.test.app",
        cpuPercent: Double = 100
    ) -> Lowbeer.ProcessInfo {
        let p = Lowbeer.ProcessInfo(pid: pid, name: name, path: path, bundleIdentifier: bundleID)
        p.cpuPercent = cpuPercent
        return p
    }

    // MARK: - Safety List

    func testSafetyListBlocksThrottle() {
        let settings = makeSettings()
        let process = makeProcess(name: "kernel_task", path: "/kernel", pid: 99)
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 100,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertNil(result)
    }

    // MARK: - Per-App Rules

    func testPerAppRuleMatches() {
        let settings = makeSettings()
        settings.rules = [
            ThrottleRule(
                identity: AppIdentity(bundleIdentifier: "com.test.app", executablePath: nil, displayName: "TestApp"),
                cpuThreshold: 50,
                sustainedSeconds: 9,
                action: .throttleTo(0.25)
            )
        ]
        let process = makeProcess(cpuPercent: 80)
        // sustainedSeconds=9, pollInterval=3 → samplesNeeded=3
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 3,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertEqual(result, .throttleTo(0.25))
    }

    func testPerAppRuleBelowThreshold() {
        let settings = makeSettings()
        settings.rules = [
            ThrottleRule(
                identity: AppIdentity(bundleIdentifier: "com.test.app", executablePath: nil, displayName: "TestApp"),
                cpuThreshold: 90,
                sustainedSeconds: 9,
                action: .stop
            )
        ]
        let process = makeProcess(cpuPercent: 50)
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 10,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertNil(result)
    }

    func testPerAppRuleInsufficientDuration() {
        let settings = makeSettings()
        settings.rules = [
            ThrottleRule(
                identity: AppIdentity(bundleIdentifier: "com.test.app", executablePath: nil, displayName: "TestApp"),
                cpuThreshold: 50,
                sustainedSeconds: 30,
                action: .stop
            )
        ]
        let process = makeProcess(cpuPercent: 100)
        // sustainedSeconds=30, pollInterval=3 → samplesNeeded=10, only have 2
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 2,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertNil(result)
    }

    func testNoFallthroughToGlobal() {
        let settings = makeSettings()
        settings.globalCPUThreshold = 10  // Very low — would trigger if falling through
        settings.rules = [
            ThrottleRule(
                identity: AppIdentity(bundleIdentifier: "com.test.app", executablePath: nil, displayName: "TestApp"),
                cpuThreshold: 90,  // Higher than actual CPU
                sustainedSeconds: 9,
                action: .stop
            )
        ]
        let process = makeProcess(cpuPercent: 50)
        // Rule matches by identity but threshold not met — should NOT fall through to global
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 100,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertNil(result)
    }

    // MARK: - Global Threshold

    func testGlobalThresholdFallback() {
        let settings = makeSettings()
        settings.globalCPUThreshold = 50
        settings.sustainedSeconds = 9
        settings.defaultAction = .stop
        // No per-app rules
        let process = makeProcess(bundleID: "com.unmatched.app", cpuPercent: 80)
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 3,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertEqual(result, .stop)
    }

    func testGlobalBelowThreshold() {
        let settings = makeSettings()
        settings.globalCPUThreshold = 80
        let process = makeProcess(bundleID: "com.unmatched.app", cpuPercent: 50)
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 100,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertNil(result)
    }

    // MARK: - Foreground

    func testForegroundSkip() {
        let settings = makeSettings()
        settings.rules = [
            ThrottleRule(
                identity: AppIdentity(bundleIdentifier: "com.test.app", executablePath: nil, displayName: "TestApp"),
                cpuThreshold: 50,
                sustainedSeconds: 9,
                action: .stop,
                throttleInBackground: true
            )
        ]
        let process = makeProcess(cpuPercent: 100)
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 100,
            settings: settings, isForeground: true, allowlist: []
        )
        XCTAssertNil(result)
    }

    // MARK: - Disabled Rule

    func testDisabledRuleSkipped() {
        let settings = makeSettings()
        settings.globalCPUThreshold = 50
        settings.sustainedSeconds = 9
        settings.rules = [
            ThrottleRule(
                identity: AppIdentity(bundleIdentifier: "com.test.app", executablePath: nil, displayName: "TestApp"),
                cpuThreshold: 10,
                sustainedSeconds: 3,
                action: .notifyOnly,
                enabled: false  // Disabled
            )
        ]
        let process = makeProcess(cpuPercent: 100)
        // Disabled rule should be skipped; global should fire
        let result = RuleEvaluator.evaluate(
            process: process, consecutiveExceedCount: 10,
            settings: settings, isForeground: false, allowlist: []
        )
        XCTAssertEqual(result, .stop)  // Global default action
    }
}
