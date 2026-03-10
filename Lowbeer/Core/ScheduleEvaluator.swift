import Foundation

/// Evaluates whether a throttle schedule is currently active.
enum ScheduleEvaluator {
    static func isActive(_ schedule: ThrottleSchedule) -> Bool {
        let calendar = Calendar.current
        let now = Date()

        let weekday = calendar.component(.weekday, from: now)
        let currentDay = DayOfWeek(rawValue: weekday)

        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let currentTime = TimeOfDay(hour: hour, minute: minute)

        let dayMatches = schedule.days.contains(currentDay)
        let inTimeWindow: Bool

        if schedule.startTime.isBeforeOrEqual(schedule.endTime) {
            // Normal range: e.g., 09:00–17:00
            inTimeWindow = schedule.startTime.isBeforeOrEqual(currentTime)
                && currentTime.isBeforeOrEqual(schedule.endTime)
        } else {
            // Wrapping range: e.g., 22:00–06:00
            inTimeWindow = schedule.startTime.isBeforeOrEqual(currentTime)
                || currentTime.isBeforeOrEqual(schedule.endTime)
        }

        let isInWindow = dayMatches && inTimeWindow

        return schedule.invertSchedule ? !isInWindow : isInWindow
    }
}
