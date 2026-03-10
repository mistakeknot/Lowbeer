import Foundation

/// Identifies an application for rule matching.
/// Matches by bundle identifier (preferred) or executable path.
struct AppIdentity: Codable, Hashable, Sendable {
    var bundleIdentifier: String?
    var executablePath: String?
    var displayName: String

    func matches(bundleID: String?, path: String) -> Bool {
        if let bid = bundleIdentifier, let candidate = bundleID, !bid.isEmpty {
            return bid == candidate
        }
        if let ep = executablePath, !ep.isEmpty {
            return path == ep || path.hasSuffix("/\(ep)")
        }
        return false
    }
}
