import AppKit
import SwiftUI

final class HelpWindowController {
    static let shared = HelpWindowController()

    private var panel: NSPanel?

    func showWindow() {
        if let existing = panel, existing.isVisible {
            existing.orderFront(nil)
            return
        }

        let helpView = HelpView()
        let hostingView = NSHostingView(rootView: helpView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "About Lowbeer"
        panel.contentView = hostingView
        panel.center()
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.orderFront(nil)

        self.panel = panel
    }
}

private struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "flame")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("Lowbeer")
                        .font(.title2.bold())
                    Text("Process Throttler for macOS")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                helpRow(icon: "gauge.high", text: "Monitors CPU usage and automatically throttles runaway processes")
                helpRow(icon: "pause.circle", text: "Uses SIGSTOP/SIGCONT to pause and resume processes")
                helpRow(icon: "shield", text: "Protected processes (system, Finder, etc.) are never throttled")
                helpRow(icon: "gear", text: "Configure thresholds, rules, and allowlists in Settings")
            }

            Spacer()

            HStack {
                Spacer()
                (Text("Named after Ainsley Lowbeer from Gibson's ") + Text("The Peripheral").italic())
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(20)
    }

    private func helpRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
        }
    }
}
