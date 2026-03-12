import SwiftUI

@main
struct LowbeerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var monitor = ProcessMonitor()
    @State private var foreground = ForegroundObserver()
    @State private var engine: ThrottleEngine?
    private let settings = LowbeerSettings.shared

    var body: some Scene {
        MenuBarExtra {
            if let engine {
                PopoverView(monitor: monitor, engine: engine, settings: settings)
            } else {
                ProgressView("Starting...")
                    .padding()
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarLabel: some View {
        HStack(spacing: 2) {
            if monitor.powerSampler.isIOReportAvailable {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(powerColor)
                if monitor.latestPower.totalWatts >= PowerSample.displayThreshold {
                    Text(String(format: "%.1fW", monitor.latestPower.totalWatts))
                        .font(.system(.caption2, design: .monospaced))
                }
            } else {
                Image(systemName: "flame")
                if monitor.totalCPU > 0 {
                    Text(String(format: "%.0f%%", monitor.totalCPU))
                        .font(.system(.caption2, design: .monospaced))
                }
            }
        }
        .onAppear {
            startMonitoring()
        }
    }

    private var powerColor: Color {
        let watts = monitor.latestPower.totalWatts
        if watts < 5 { return .green }
        if watts < 10 { return .yellow }
        if watts < 20 { return .orange }
        return .red
    }

    private func startMonitoring() {
        monitor.pollInterval = settings.pollInterval
        monitor.start()
        foreground.start()

        let eng = ThrottleEngine(monitor: monitor, foreground: foreground, settings: settings)
        engine = eng

        // Evaluate processes on each poll cycle
        Timer.scheduledTimer(withTimeInterval: settings.pollInterval + 0.5, repeats: true) { _ in
            eng.evaluate()
        }
    }
}
