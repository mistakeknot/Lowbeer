import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        LowbeerNotificationManager.shared.setup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Resume all throttled processes on quit so we don't leave zombies
        // This is handled by the app's ThrottleEngine.resumeAll()
    }
}
