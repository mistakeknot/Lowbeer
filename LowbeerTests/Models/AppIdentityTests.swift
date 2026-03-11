import XCTest
@testable import Lowbeer

final class AppIdentityTests: XCTestCase {

    func testMatchesBundleID() {
        let identity = AppIdentity(bundleIdentifier: "com.example.app", executablePath: nil, displayName: "Example")
        XCTAssertTrue(identity.matches(bundleID: "com.example.app", path: "/usr/bin/anything"))
    }

    func testBundleIDMismatch() {
        let identity = AppIdentity(bundleIdentifier: "com.example.app", executablePath: nil, displayName: "Example")
        XCTAssertFalse(identity.matches(bundleID: "com.other.app", path: "/usr/bin/anything"))
    }

    func testMatchesExactPath() {
        let identity = AppIdentity(bundleIdentifier: nil, executablePath: "/Applications/MyApp.app/Contents/MacOS/MyApp", displayName: "MyApp")
        XCTAssertTrue(identity.matches(bundleID: nil, path: "/Applications/MyApp.app/Contents/MacOS/MyApp"))
    }

    func testMatchesPathSuffix() {
        let identity = AppIdentity(bundleIdentifier: nil, executablePath: "MyApp", displayName: "MyApp")
        XCTAssertTrue(identity.matches(bundleID: nil, path: "/Applications/MyApp.app/Contents/MacOS/MyApp"))
    }

    func testNoBundleIDFallsToPath() {
        let identity = AppIdentity(bundleIdentifier: nil, executablePath: "chrome", displayName: "Chrome")
        XCTAssertTrue(identity.matches(bundleID: "com.google.chrome", path: "/Applications/Google Chrome.app/Contents/MacOS/chrome"))
    }

    func testNoMatchReturnsFalse() {
        let identity = AppIdentity(bundleIdentifier: "com.example.app", executablePath: nil, displayName: "Example")
        XCTAssertFalse(identity.matches(bundleID: nil, path: "/usr/bin/other"))
    }

    func testEmptyBundleIDIgnored() {
        let identity = AppIdentity(bundleIdentifier: "", executablePath: "myapp", displayName: "MyApp")
        XCTAssertTrue(identity.matches(bundleID: nil, path: "/usr/local/bin/myapp"))
    }

    func testEmptyPathNoMatch() {
        let identity = AppIdentity(bundleIdentifier: nil, executablePath: "", displayName: "Empty")
        XCTAssertFalse(identity.matches(bundleID: nil, path: "/usr/bin/anything"))
    }
}
