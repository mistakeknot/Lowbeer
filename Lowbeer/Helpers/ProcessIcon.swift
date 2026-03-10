import AppKit
import Foundation

/// Looks up application icons for processes.
enum ProcessIcon {
    private static var cache = [String: NSImage]()
    private static let genericIcon = NSImage(named: NSImage.applicationIconName)
        ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        ?? NSImage()

    /// Returns the app icon for a given path, with caching.
    static func icon(for path: String, bundleIdentifier: String? = nil) -> NSImage {
        let key = bundleIdentifier ?? path

        if let cached = cache[key] { return cached }

        // Try NSRunningApplication first
        if let bid = bundleIdentifier {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            if let icon = apps.first?.icon {
                cache[key] = icon
                return icon
            }
        }

        // Try getting icon from the executable path's bundle
        if let bundle = Bundle(path: path)?.bundleURL ?? bundleURL(from: path) {
            let icon = NSWorkspace.shared.icon(forFile: bundle.path)
            cache[key] = icon
            return icon
        }

        // Try icon from file path directly
        if FileManager.default.fileExists(atPath: path) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            cache[key] = icon
            return icon
        }

        return genericIcon
    }

    /// Walk up from a binary path to find its .app bundle, if any.
    private static func bundleURL(from executablePath: String) -> URL? {
        var url = URL(fileURLWithPath: executablePath)
        while url.pathComponents.count > 1 {
            url = url.deletingLastPathComponent()
            if url.pathExtension == "app" {
                return url
            }
        }
        return nil
    }
}
