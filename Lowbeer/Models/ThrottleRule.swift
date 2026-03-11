import Foundation

enum ThrottleAction: Codable, Hashable, Sendable {
    case stop
    case throttleTo(Double)
    case notifyOnly
}

struct DayOfWeek: Codable, Hashable, Sendable {
    let rawValue: Int  // 1=Sunday ... 7=Saturday (Calendar convention)

    static let sunday = DayOfWeek(rawValue: 1)
    static let monday = DayOfWeek(rawValue: 2)
    static let tuesday = DayOfWeek(rawValue: 3)
    static let wednesday = DayOfWeek(rawValue: 4)
    static let thursday = DayOfWeek(rawValue: 5)
    static let friday = DayOfWeek(rawValue: 6)
    static let saturday = DayOfWeek(rawValue: 7)

    static let weekdays: Set<DayOfWeek> = [.monday, .tuesday, .wednesday, .thursday, .friday]
    static let all: Set<DayOfWeek> = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
}

struct TimeOfDay: Codable, Hashable, Sendable {
    var hour: Int    // 0-23
    var minute: Int  // 0-59

    func isBeforeOrEqual(_ other: TimeOfDay) -> Bool {
        (hour, minute) <= (other.hour, other.minute)
    }

    var description: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

struct ThrottleSchedule: Codable, Hashable, Sendable {
    var days: Set<DayOfWeek>
    var startTime: TimeOfDay
    var endTime: TimeOfDay
    var invertSchedule: Bool = false  // true = active OUTSIDE the window
}

struct ThrottleRule: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var identity: AppIdentity
    var cpuThreshold: Double           // trigger when CPU > this % (e.g., 80)
    var sustainedSeconds: Int          // must exceed for this many seconds (e.g., 30)
    var action: ThrottleAction         // .stop, .throttleTo(Double), .notifyOnly
    var schedule: ThrottleSchedule?    // optional time-based activation
    var throttleInBackground: Bool     // only throttle when not foreground
    var enabled: Bool
    var isDefault: Bool                // true for built-in vibecoding defaults

    init(
        identity: AppIdentity,
        cpuThreshold: Double = 80,
        sustainedSeconds: Int = 30,
        action: ThrottleAction = .stop,
        schedule: ThrottleSchedule? = nil,
        throttleInBackground: Bool = true,
        enabled: Bool = true,
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.identity = identity
        self.cpuThreshold = cpuThreshold
        self.sustainedSeconds = sustainedSeconds
        self.action = action
        self.schedule = schedule
        self.throttleInBackground = throttleInBackground
        self.enabled = enabled
        self.isDefault = isDefault
    }

    // Custom decoder: decodeIfPresent for isDefault so existing JSON without
    // the key decodes safely as false instead of crashing.
    enum CodingKeys: String, CodingKey {
        case id, identity, cpuThreshold, sustainedSeconds, action
        case schedule, throttleInBackground, enabled, isDefault
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        identity = try c.decode(AppIdentity.self, forKey: .identity)
        cpuThreshold = try c.decode(Double.self, forKey: .cpuThreshold)
        sustainedSeconds = try c.decode(Int.self, forKey: .sustainedSeconds)
        action = try c.decode(ThrottleAction.self, forKey: .action)
        schedule = try c.decodeIfPresent(ThrottleSchedule.self, forKey: .schedule)
        throttleInBackground = try c.decode(Bool.self, forKey: .throttleInBackground)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
    }
}
