import Foundation

enum ThrottleMode: String, Codable {
    case automatic
    case askFirst
}

@Observable
final class LowbeerSettings {
    static let shared = LowbeerSettings()

    var globalCPUThreshold: Double {
        didSet { save() }
    }
    var sustainedSeconds: Int {
        didSet { save() }
    }
    var defaultAction: ThrottleAction {
        didSet { save() }
    }
    var throttleMode: ThrottleMode {
        didSet { save() }
    }
    var pollInterval: TimeInterval {
        didSet { save() }
    }
    var launchAtLogin: Bool {
        didSet { save() }
    }
    var showInMenuBar: Bool {
        didSet { save() }
    }
    var notificationsEnabled: Bool {
        didSet { save() }
    }
    var isPaused: Bool {
        didSet { save() }
    }

    // Per-app rules stored as JSON file
    var rules: [ThrottleRule] {
        didSet { saveRules() }
    }

    // User-managed allowlist additions
    var userAllowlist: [AppIdentity] {
        didSet { saveAllowlist() }
    }

    private let defaults: UserDefaults
    private var isSavingRules = false

    /// Test-only initializer. Visible via @testable import.
    init(forTesting: Bool) {
        self.defaults = UserDefaults(suiteName: "com.lowbeer.tests.\(UUID().uuidString)")!
        self.globalCPUThreshold = 80
        self.sustainedSeconds = 30
        self.defaultAction = .stop
        self.throttleMode = .automatic
        self.pollInterval = 3
        self.launchAtLogin = false
        self.showInMenuBar = true
        self.notificationsEnabled = true
        self.isPaused = false
        self.rules = []
        self.userAllowlist = []
    }

    private init() {
        self.defaults = UserDefaults.standard
        self.globalCPUThreshold = defaults.double(forKey: "globalCPUThreshold").nonZero ?? 80
        self.sustainedSeconds = defaults.integer(forKey: "sustainedSeconds").nonZero ?? 30
        self.pollInterval = defaults.double(forKey: "pollInterval").nonZero ?? 3
        self.launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        self.showInMenuBar = defaults.object(forKey: "showInMenuBar") as? Bool ?? true
        self.notificationsEnabled = defaults.object(forKey: "notificationsEnabled") as? Bool ?? true
        self.isPaused = defaults.bool(forKey: "isPaused")
        self.throttleMode = ThrottleMode(rawValue: defaults.string(forKey: "throttleMode") ?? "") ?? .automatic
        self.rules = Self.loadJSON("lowbeer_rules.json") ?? []
        self.userAllowlist = Self.loadJSON("lowbeer_allowlist.json") ?? []

        if let actionData = defaults.data(forKey: "defaultAction"),
           let action = try? JSONDecoder().decode(ThrottleAction.self, from: actionData) {
            self.defaultAction = action
        } else {
            self.defaultAction = .stop
        }

        // Seed vibecoding defaults on first launch only
        if !defaults.bool(forKey: "hasSeededDefaults") {
            if rules.isEmpty {
                rules = DefaultRules.all
            }
            defaults.set(true, forKey: "hasSeededDefaults")
        }

        // Ensure custom rules precede defaults for first-match semantics
        rules.sort { !$0.isDefault && $1.isDefault }

        // didSet observers are suppressed during init, so write explicitly
        saveRules()
    }

    private func save() {
        defaults.set(globalCPUThreshold, forKey: "globalCPUThreshold")
        defaults.set(sustainedSeconds, forKey: "sustainedSeconds")
        defaults.set(pollInterval, forKey: "pollInterval")
        defaults.set(launchAtLogin, forKey: "launchAtLogin")
        defaults.set(showInMenuBar, forKey: "showInMenuBar")
        defaults.set(notificationsEnabled, forKey: "notificationsEnabled")
        defaults.set(isPaused, forKey: "isPaused")
        defaults.set(throttleMode.rawValue, forKey: "throttleMode")
        if let data = try? JSONEncoder().encode(defaultAction) {
            defaults.set(data, forKey: "defaultAction")
        }
    }

    private func saveRules() {
        guard !isSavingRules else { return }
        isSavingRules = true
        // Sort in-place so the live array matches disk order (custom before default).
        // The guard prevents didSet recursion from the sort assignment.
        rules.sort { !$0.isDefault && $1.isDefault }
        Self.saveJSON(rules, to: "lowbeer_rules.json")
        isSavingRules = false
    }

    private func saveAllowlist() {
        Self.saveJSON(userAllowlist, to: "lowbeer_allowlist.json")
    }

    private static var appSupportURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lowbeer", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func loadJSON<T: Decodable>(_ filename: String) -> T? {
        let url = appSupportURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func saveJSON<T: Encodable>(_ value: T, to filename: String) {
        let url = appSupportURL.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
