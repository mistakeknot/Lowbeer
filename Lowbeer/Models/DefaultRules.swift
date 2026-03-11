import Foundation

/// Pre-built throttle rules for vibecoding workflows.
/// Seeded on first launch so Lowbeer works out-of-the-box with AI tools and terminals.
enum DefaultRules {

    // MARK: - Terminal Emulators
    // High threshold, background-only, duty-cycle (never freeze a foreground terminal)

    static let terminalRules: [ThrottleRule] = [
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.mitchellh.ghostty", displayName: "Ghostty"),
            cpuThreshold: 150, sustainedSeconds: 30,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "dev.warp.Warp-Stable", displayName: "Warp"),
            cpuThreshold: 150, sustainedSeconds: 30,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.googlecode.iterm2", displayName: "iTerm2"),
            cpuThreshold: 150, sustainedSeconds: 30,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal"),
            cpuThreshold: 150, sustainedSeconds: 30,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "net.kovidgoyal.kitty", displayName: "Kitty"),
            cpuThreshold: 150, sustainedSeconds: 30,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        // Alacritty: no reliable bundle ID from Homebrew installs, match by executable path
        ThrottleRule(
            identity: AppIdentity(executablePath: "alacritty", displayName: "Alacritty"),
            cpuThreshold: 150, sustainedSeconds: 30,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
    ]

    // MARK: - AI IDE Helpers
    // Moderate threshold, background-only, duty-cycle

    static let aiToolRules: [ThrottleRule] = [
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.todesktop.cursor", displayName: "Cursor"),
            cpuThreshold: 120, sustainedSeconds: 60,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.microsoft.VSCode", displayName: "VS Code"),
            cpuThreshold: 120, sustainedSeconds: 60,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.codeium.windsurf", displayName: "Windsurf"),
            cpuThreshold: 120, sustainedSeconds: 60,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
        // Claude Code: CLI tool, no bundle ID — match by executable name
        ThrottleRule(
            identity: AppIdentity(executablePath: "claude", displayName: "Claude Code"),
            cpuThreshold: 120, sustainedSeconds: 60,
            action: .throttleTo(0.5), throttleInBackground: true, isDefault: true
        ),
    ]

    // MARK: - Build Tools
    // Worker processes spawned by AI tools — without explicit rules these hit
    // the global 80% threshold with full SIGSTOP, which is too aggressive.

    static let buildToolRules: [ThrottleRule] = [
        ThrottleRule(
            identity: AppIdentity(executablePath: "node", displayName: "Node.js"),
            cpuThreshold: 150, sustainedSeconds: 45,
            action: .throttleTo(0.5), throttleInBackground: false, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(executablePath: "python3", displayName: "Python"),
            cpuThreshold: 150, sustainedSeconds: 45,
            action: .throttleTo(0.5), throttleInBackground: false, isDefault: true
        ),
    ]

    // MARK: - Local LLMs
    // Very high threshold, notify-only — user intentionally runs inference,
    // stopping it would break the generation mid-stream.

    static let localLLMRules: [ThrottleRule] = [
        ThrottleRule(
            identity: AppIdentity(executablePath: "ollama", displayName: "Ollama"),
            cpuThreshold: 300, sustainedSeconds: 120,
            action: .notifyOnly, throttleInBackground: false, isDefault: true
        ),
        ThrottleRule(
            identity: AppIdentity(bundleIdentifier: "com.lmstudio.app", displayName: "LM Studio"),
            cpuThreshold: 300, sustainedSeconds: 120,
            action: .notifyOnly, throttleInBackground: false, isDefault: true
        ),
    ]

    // MARK: - All Defaults

    static let all: [ThrottleRule] =
        terminalRules + aiToolRules + buildToolRules + localLLMRules
}
