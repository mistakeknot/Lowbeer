import XCTest
@testable import Lowbeer

final class ThrottleEngineTests: XCTestCase {

    private var settings: LowbeerSettings!
    private var monitor: ProcessMonitor!
    private var foreground: MockForegroundObserver!
    private var engine: ThrottleEngine!

    override func setUp() {
        super.setUp()
        settings = LowbeerSettings(forTesting: true)
        settings.globalCPUThreshold = 80
        settings.sustainedSeconds = 9  // 3 samples at 3s poll
        settings.pollInterval = 3
        settings.defaultAction = .stop
        settings.throttleMode = .automatic

        monitor = ProcessMonitor(pollInterval: 3)
        foreground = MockForegroundObserver()
        engine = ThrottleEngine(monitor: monitor, foreground: foreground, settings: settings)
    }

    override func tearDown() {
        engine.resumeAll()
        engine = nil
        monitor = nil
        foreground = nil
        settings = nil
        super.tearDown()
    }

    /// Inject processes directly into the monitor.
    private func setProcesses(_ processes: [Lowbeer.ProcessInfo]) {
        monitor.setProcessesForTesting(processes)
    }

    private func makeProcess(
        name: String = "TestApp",
        path: String = "/Applications/TestApp.app/Contents/MacOS/TestApp",
        pid: pid_t = 500,
        bundleID: String? = "com.test.app",
        cpuPercent: Double = 100,
        startTime: timeval = timeval(tv_sec: 1000, tv_usec: 0)
    ) -> Lowbeer.ProcessInfo {
        let p = Lowbeer.ProcessInfo(pid: pid, name: name, path: path, bundleIdentifier: bundleID, startTime: startTime)
        p.cpuPercent = cpuPercent
        return p
    }

    // MARK: - Paused

    func testPausedSkipsEvaluation() {
        settings.isPaused = true
        let process = makeProcess(cpuPercent: 100)
        setProcesses([process])

        // Run many cycles — nothing should be throttled
        for _ in 0..<20 { engine.evaluate() }

        XCTAssertEqual(engine.throttledCount, 0)
    }

    // MARK: - Below Threshold

    func testBelowThresholdNoThrottle() {
        let process = makeProcess(cpuPercent: 50) // below 80% global
        setProcesses([process])

        for _ in 0..<20 { engine.evaluate() }

        XCTAssertEqual(engine.throttledCount, 0)
        XCTAssertFalse(process.isThrottled)
    }

    // MARK: - Above Threshold

    func testAboveThresholdCreatesSession() {
        let process = makeProcess(cpuPercent: 100)
        setProcesses([process])

        // Need 3 samples (sustainedSeconds=9, pollInterval=3)
        for _ in 0..<4 { engine.evaluate() }

        XCTAssertEqual(engine.throttledCount, 1)
        XCTAssertTrue(process.isThrottled)
    }

    // MARK: - Drops Below Threshold

    func testDropsBelowThresholdResumes() {
        let process = makeProcess(cpuPercent: 100)
        setProcesses([process])

        // Throttle it
        for _ in 0..<4 { engine.evaluate() }
        XCTAssertEqual(engine.throttledCount, 1)

        // Drop CPU below threshold
        process.cpuPercent = 10
        engine.evaluate()

        XCTAssertEqual(engine.throttledCount, 0)
        XCTAssertFalse(process.isThrottled)
    }

    // MARK: - Foreground Auto-Resume

    func testForegroundAutoResume() {
        let process = makeProcess(cpuPercent: 100)
        setProcesses([process])

        // Throttle it
        for _ in 0..<4 { engine.evaluate() }
        XCTAssertEqual(engine.throttledCount, 1)

        // Make it foreground
        foreground.setForeground(pid: process.pid)
        engine.evaluate()

        XCTAssertEqual(engine.throttledCount, 0)
        XCTAssertFalse(process.isThrottled)
    }

    // MARK: - PID Reuse Detection

    func testPIDReuseDetection() {
        let process = makeProcess(pid: 500, cpuPercent: 100, startTime: timeval(tv_sec: 1000, tv_usec: 0))
        setProcesses([process])

        // Throttle it
        for _ in 0..<4 { engine.evaluate() }
        XCTAssertEqual(engine.throttledCount, 1)

        // New process reuses same PID but different startTime
        let newProcess = makeProcess(pid: 500, cpuPercent: 50, startTime: timeval(tv_sec: 2000, tv_usec: 0))
        setProcesses([newProcess])
        engine.evaluate()

        // Session should be cleaned up due to startTime mismatch
        XCTAssertEqual(engine.throttledCount, 0)
        XCTAssertFalse(newProcess.isThrottled)
    }

    // MARK: - Dead Process Cleanup

    func testDeadProcessCleanup() {
        let process = makeProcess(cpuPercent: 100)
        setProcesses([process])

        // Throttle it
        for _ in 0..<4 { engine.evaluate() }
        XCTAssertEqual(engine.throttledCount, 1)

        // Process disappears (not in monitor.processes)
        setProcesses([])
        engine.evaluate()

        XCTAssertEqual(engine.throttledCount, 0)
    }

    // MARK: - Manual Resume

    func testResumeManual() {
        let process = makeProcess(cpuPercent: 100)
        setProcesses([process])

        for _ in 0..<4 { engine.evaluate() }
        XCTAssertEqual(engine.throttledCount, 1)

        engine.resume(pid: process.pid)

        XCTAssertEqual(engine.throttledCount, 0)
        XCTAssertFalse(process.isThrottled)
    }

    // MARK: - Resume All

    func testResumeAll() {
        let p1 = makeProcess(pid: 500, cpuPercent: 100)
        let p2 = makeProcess(name: "Other", pid: 501, bundleID: nil, cpuPercent: 100)
        setProcesses([p1, p2])

        for _ in 0..<4 { engine.evaluate() }
        XCTAssertEqual(engine.throttledCount, 2)

        engine.resumeAll()

        XCTAssertEqual(engine.throttledCount, 0)
        XCTAssertFalse(p1.isThrottled)
        XCTAssertFalse(p2.isThrottled)
    }

    // MARK: - No Fallthrough

    func testNoFallthroughOnRuleMatch() {
        settings.globalCPUThreshold = 10  // Very low
        settings.rules = [
            ThrottleRule(
                identity: AppIdentity(bundleIdentifier: "com.test.app", executablePath: nil, displayName: "TestApp"),
                cpuThreshold: 200,  // Impossibly high
                sustainedSeconds: 9,
                action: .stop
            )
        ]

        let process = makeProcess(cpuPercent: 50)
        setProcesses([process])

        for _ in 0..<20 { engine.evaluate() }

        // Rule matched identity but threshold not met — should NOT fall through to global
        XCTAssertEqual(engine.throttledCount, 0)
    }

    // MARK: - Notify Only

    func testNotifyOnlyKeepsSessionForDedup() {
        settings.globalCPUThreshold = 50
        settings.sustainedSeconds = 9
        settings.defaultAction = .notifyOnly

        let process = makeProcess(bundleID: "com.unmatched.app", cpuPercent: 100)
        setProcesses([process])

        for _ in 0..<4 { engine.evaluate() }

        // notifyOnly keeps a session to prevent re-notification every poll cycle.
        // The session exists but the process is NOT marked as throttled (no SIGSTOP sent).
        XCTAssertEqual(engine.throttledCount, 1)
        XCTAssertFalse(process.isThrottled)
    }

    func testNotifyOnlyClearsWhenCPUDrops() {
        settings.globalCPUThreshold = 50
        settings.sustainedSeconds = 9
        settings.defaultAction = .notifyOnly

        let process = makeProcess(bundleID: "com.unmatched.app", cpuPercent: 100)
        setProcesses([process])

        for _ in 0..<4 { engine.evaluate() }
        XCTAssertEqual(engine.throttledCount, 1)

        // CPU drops below threshold — session should be cleaned up
        process.cpuPercent = 10
        engine.evaluate()
        XCTAssertEqual(engine.throttledCount, 0)
    }
}
