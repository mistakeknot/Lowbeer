import SwiftUI

struct PopoverView: View {
    let monitor: ProcessMonitor
    let engine: ThrottleEngine
    let settings: LowbeerSettings

    private var displayedProcesses: [ProcessInfo] {
        Array(monitor.processes.prefix(15))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            Divider()

            // Process list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedProcesses) { process in
                        ProcessRowView(
                            process: process,
                            systemWatts: monitor.latestPower.totalWatts,
                            totalCPU: monitor.totalCPU,
                            onThrottle: { engine.throttle(pid: process.pid) },
                            onResume: { engine.resume(pid: process.pid) }
                        )
                        if process.id != displayedProcesses.last?.id {
                            Divider().padding(.horizontal, 12)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 340)

            // Throttled processes section
            if engine.throttledCount > 0 {
                Divider()
                throttledSection
            }
        }
        .frame(width: 400)
    }

    private var headerView: some View {
        HStack {
            Image(systemName: "flame")
                .foregroundStyle(.orange)
            Text("Lowbeer")
                .font(.headline)

            Spacer()

            Text(String(format: "CPU: %.0f%%", monitor.totalCPU))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            // Pause/Resume all button
            Button(action: {
                if settings.isPaused {
                    settings.isPaused = false
                } else {
                    engine.resumeAll()
                    settings.isPaused = true
                }
            }) {
                Image(systemName: settings.isPaused ? "play.circle" : "pause.circle")
            }
            .buttonStyle(.borderless)
            .help(settings.isPaused ? "Resume throttling" : "Pause all throttling")

            // Help
            Button {
                HelpWindowController.shared.showWindow()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.borderless)
            .help("About Lowbeer")

            // Settings
            Button {
                SettingsWindowController.shared.showWindow()
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help("Settings")

            // Quit
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Quit Lowbeer")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var throttledSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(.orange)
                Text("\(engine.throttledCount) process\(engine.throttledCount == 1 ? "" : "es") throttled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(engine.throttledProcesses, id: \.pid) { session in
                HStack {
                    Text(session.processName)
                        .font(.caption)
                    Text("(\(session.pid))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("—")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    switch session.action {
                    case .stop:
                        Text("stopped \(session.elapsedDescription)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    case .throttleTo(let target):
                        Text("\(Int(target * 100))% limit")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    case .notifyOnly:
                        EmptyView()
                    }

                    Spacer()

                    Button("Resume") {
                        engine.resume(pid: session.pid)
                    }
                    .font(.caption2)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
