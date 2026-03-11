import XCTest
@testable import Lowbeer

final class ScheduleEvaluatorTests: XCTestCase {

    /// Helper to create a Date for a specific weekday, hour, and minute.
    /// weekday: 1=Sunday, 2=Monday ... 7=Saturday (Calendar convention)
    private func makeDate(weekday: Int, hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current

        // Find the next date matching this weekday from a fixed reference
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        components.second = 0

        // Use a known Monday (2026-03-09) as anchor
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 0))!
        return calendar.nextDate(after: anchor, matching: components, matchingPolicy: .nextTime)!
    }

    // MARK: - Normal range (start <= end)

    func testNormalRangeInside() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 17, minute: 0)
        )
        // Wednesday 10:00
        let date = makeDate(weekday: 4, hour: 10, minute: 0)
        XCTAssertTrue(ScheduleEvaluator.isActive(schedule, at: date))
    }

    func testNormalRangeOutside() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 17, minute: 0)
        )
        // Wednesday 20:00
        let date = makeDate(weekday: 4, hour: 20, minute: 0)
        XCTAssertFalse(ScheduleEvaluator.isActive(schedule, at: date))
    }

    // MARK: - Wrapping range (start > end, crosses midnight)

    func testWrappingRangeAfterMidnight() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 22, minute: 0),
            endTime: TimeOfDay(hour: 6, minute: 0)
        )
        // Wednesday 02:00
        let date = makeDate(weekday: 4, hour: 2, minute: 0)
        XCTAssertTrue(ScheduleEvaluator.isActive(schedule, at: date))
    }

    func testWrappingRangeBeforeMidnight() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 22, minute: 0),
            endTime: TimeOfDay(hour: 6, minute: 0)
        )
        // Wednesday 23:00
        let date = makeDate(weekday: 4, hour: 23, minute: 0)
        XCTAssertTrue(ScheduleEvaluator.isActive(schedule, at: date))
    }

    func testWrappingRangeOutside() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 22, minute: 0),
            endTime: TimeOfDay(hour: 6, minute: 0)
        )
        // Wednesday 12:00
        let date = makeDate(weekday: 4, hour: 12, minute: 0)
        XCTAssertFalse(ScheduleEvaluator.isActive(schedule, at: date))
    }

    // MARK: - Day matching

    func testDayMismatch() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,  // Mon-Fri
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 17, minute: 0)
        )
        // Sunday 10:00
        let date = makeDate(weekday: 1, hour: 10, minute: 0)
        XCTAssertFalse(ScheduleEvaluator.isActive(schedule, at: date))
    }

    // MARK: - Inverted schedule

    func testInvertedInsideWindow() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 17, minute: 0),
            invertSchedule: true
        )
        // Wednesday 10:00 — inside window, but inverted → false
        let date = makeDate(weekday: 4, hour: 10, minute: 0)
        XCTAssertFalse(ScheduleEvaluator.isActive(schedule, at: date))
    }

    func testInvertedOutsideWindow() {
        let schedule = ThrottleSchedule(
            days: DayOfWeek.weekdays,
            startTime: TimeOfDay(hour: 9, minute: 0),
            endTime: TimeOfDay(hour: 17, minute: 0),
            invertSchedule: true
        )
        // Wednesday 20:00 — outside window, inverted → true
        let date = makeDate(weekday: 4, hour: 20, minute: 0)
        XCTAssertTrue(ScheduleEvaluator.isActive(schedule, at: date))
    }
}
