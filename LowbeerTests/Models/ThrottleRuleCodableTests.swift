import XCTest
@testable import Lowbeer

final class ThrottleRuleCodableTests: XCTestCase {

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - ThrottleAction

    func testActionStopRoundTrip() throws {
        let action: ThrottleAction = .stop
        let decoded = try roundTrip(action)
        XCTAssertEqual(decoded, action)
    }

    func testActionThrottleToRoundTrip() throws {
        let action: ThrottleAction = .throttleTo(0.5)
        let decoded = try roundTrip(action)
        XCTAssertEqual(decoded, action)
    }

    func testActionNotifyOnlyRoundTrip() throws {
        let action: ThrottleAction = .notifyOnly
        let decoded = try roundTrip(action)
        XCTAssertEqual(decoded, action)
    }

    // MARK: - DayOfWeek

    func testDayOfWeekCodable() throws {
        let day = DayOfWeek.wednesday
        let decoded = try roundTrip(day)
        XCTAssertEqual(decoded, day)
    }

    // MARK: - TimeOfDay

    func testTimeOfDayCodable() throws {
        let time = TimeOfDay(hour: 14, minute: 30)
        let decoded = try roundTrip(time)
        XCTAssertEqual(decoded, time)
    }

    func testTimeOfDayIsBeforeOrEqual() {
        let early = TimeOfDay(hour: 9, minute: 0)
        let late = TimeOfDay(hour: 17, minute: 0)
        let same = TimeOfDay(hour: 9, minute: 0)

        XCTAssertTrue(early.isBeforeOrEqual(late))
        XCTAssertFalse(late.isBeforeOrEqual(early))
        XCTAssertTrue(early.isBeforeOrEqual(same))
    }

    // MARK: - ThrottleSchedule

    func testScheduleRoundTrip() throws {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 17, minute: 0),
            invertSchedule: true
        )
        let decoded = try roundTrip(schedule)
        XCTAssertEqual(decoded, schedule)
    }

    // MARK: - ThrottleRule

    func testRuleRoundTrip() throws {
        let rule = ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.example.app", executablePath: nil, displayName: "Example"),
            cpuThreshold: 50,
            sustainedSeconds: 15,
            action: .throttleTo(0.25),
            schedule: ThrottleSchedule(
                days: [.monday, .friday],
                startTime: TimeOfDay(hour: 22, minute: 0),
                endTime: TimeOfDay(hour: 6, minute: 0)
            ),
            throttleInBackground: false,
            enabled: true
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ThrottleRule.self, from: data)

        XCTAssertEqual(decoded.id, rule.id)
        XCTAssertEqual(decoded.identity, rule.identity)
        XCTAssertEqual(decoded.cpuThreshold, rule.cpuThreshold)
        XCTAssertEqual(decoded.sustainedSeconds, rule.sustainedSeconds)
        XCTAssertEqual(decoded.action, rule.action)
        XCTAssertEqual(decoded.schedule, rule.schedule)
        XCTAssertEqual(decoded.throttleInBackground, rule.throttleInBackground)
        XCTAssertEqual(decoded.enabled, rule.enabled)
        XCTAssertEqual(decoded.isDefault, rule.isDefault)
    }

    // MARK: - isDefault field

    func testIsDefaultRoundTrip() throws {
        let rule = ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.test.app", displayName: "Test"),
            isDefault: true
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ThrottleRule.self, from: data)
        XCTAssertTrue(decoded.isDefault)
    }

    func testIsDefaultFalseByDefault() throws {
        let rule = ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.test.app", displayName: "Test")
        )
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(ThrottleRule.self, from: data)
        XCTAssertFalse(decoded.isDefault)
    }

    func testMigrationFromJSONWithoutIsDefault() throws {
        // Simulates loading rules saved by a pre-isDefault version.
        // The key "isDefault" is absent — decoder must not crash.
        let json = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "identity": {
                "bundleIdentifier": "com.test.app",
                "displayName": "Test"
            },
            "cpuThreshold": 80,
            "sustainedSeconds": 30,
            "action": { "stop": {} },
            "throttleInBackground": true,
            "enabled": true
        }
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ThrottleRule.self, from: data)
        XCTAssertFalse(decoded.isDefault, "Missing isDefault key should decode as false")
        XCTAssertEqual(decoded.cpuThreshold, 80)
        XCTAssertTrue(decoded.enabled)
    }
}
