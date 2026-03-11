import XCTest
@testable import Lowbeer

final class SafetyListTests: XCTestCase {

    func testProtectedNames() {
        XCTAssertTrue(SafetyList.isProtected(name: "kernel_task", path: "/kernel", pid: 99, allowlist: []))
        XCTAssertTrue(SafetyList.isProtected(name: "Lowbeer", path: "/usr/local/bin/Lowbeer", pid: 99, allowlist: []))
        XCTAssertTrue(SafetyList.isProtected(name: "WindowServer", path: "/System/Library/Frameworks", pid: 99, allowlist: []))
    }

    func testProtectedPaths() {
        XCTAssertTrue(SafetyList.isProtected(name: "unknown", path: "/System/Library/foo", pid: 99, allowlist: []))
        XCTAssertTrue(SafetyList.isProtected(name: "unknown", path: "/usr/libexec/bar", pid: 99, allowlist: []))
        XCTAssertTrue(SafetyList.isProtected(name: "unknown", path: "/usr/sbin/baz", pid: 99, allowlist: []))
    }

    func testSpecialPIDs() {
        XCTAssertTrue(SafetyList.isProtected(name: "unknown", path: "/unknown", pid: 0, allowlist: []))
        XCTAssertTrue(SafetyList.isProtected(name: "unknown", path: "/unknown", pid: 1, allowlist: []))
    }

    func testOwnProcess() {
        let ownPID = Foundation.ProcessInfo.processInfo.processIdentifier
        XCTAssertTrue(SafetyList.isProtected(name: "test", path: "/test", pid: ownPID, allowlist: []))
    }

    func testUnprotectedProcess() {
        // PID 500 is unlikely to be our own process
        let pid: pid_t = 32000
        guard pid != Foundation.ProcessInfo.processInfo.processIdentifier else { return }
        XCTAssertFalse(SafetyList.isProtected(name: "MyApp", path: "/Applications/MyApp.app/Contents/MacOS/MyApp", pid: pid, allowlist: []))
    }

    func testUserAllowlist() {
        let allowlist = [
            AppIdentity(bundleIdentifier: nil, executablePath: "/Applications/AllowedApp.app/Contents/MacOS/AllowedApp", displayName: "AllowedApp")
        ]
        let pid: pid_t = 32001
        guard pid != Foundation.ProcessInfo.processInfo.processIdentifier else { return }
        XCTAssertTrue(SafetyList.isProtected(
            name: "AllowedApp",
            path: "/Applications/AllowedApp.app/Contents/MacOS/AllowedApp",
            pid: pid,
            allowlist: allowlist
        ))
    }

    func testAllowlistDisplayNameMatch() {
        let allowlist = [
            AppIdentity(bundleIdentifier: nil, executablePath: nil, displayName: "SpecialApp")
        ]
        let pid: pid_t = 32002
        guard pid != Foundation.ProcessInfo.processInfo.processIdentifier else { return }
        XCTAssertTrue(SafetyList.isProtected(
            name: "SpecialApp",
            path: "/usr/local/bin/specialapp",
            pid: pid,
            allowlist: allowlist
        ))
    }
}
