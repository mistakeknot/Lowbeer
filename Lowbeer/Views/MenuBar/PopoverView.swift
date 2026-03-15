import SwiftUI

enum SortColumn: String {
    case cpu, ram, energy
}

struct PopoverView: View {
    let monitor: ProcessMonitor
    let engine: ThrottleEngine
    let settings: LowbeerSettings

    @State private var sortColumn: SortColumn = .cpu
    @State private var sortAscending: Bool = false

    private var showEnergy: Bool {
        monitor.latestPower.totalWatts >= PowerSample.displayThreshold && monitor.totalCPU > 0
    }

    private var displayedProcesses: [ProcessInfo] {
        let all = Array(monitor.processes.prefix(15))
        switch sortColumn {
        case .cpu:
            return sortAscending ? all.sorted { $0.cpuPercent < $1.cpuPercent }
                                 : all  // Already sorted by CPU desc from ProcessMonitor
        case .ram:
            return sortAscending ? all.sorted { $0.residentBytes < $1.residentBytes }
                                 : all.sorted { $0.residentBytes > $1.residentBytes }
        case .energy:
            let total = monitor.totalCPU
            guard total > 0 else { return all }
            return sortAscending ? all.sorted { $0.cpuPercent / total < $1.cpuPercent / total }
                                 : all.sorted { $0.cpuPercent / total > $1.cpuPercent / total }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerView
            Divider()

            // Column headers
            columnHeaders
            Divider()

            // Process list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedProcesses) { process in
                        ProcessRowView(
                            process: process,
                            systemWatts: monitor.latestPower.totalWatts,
                            totalCPU: monitor.totalCPU,
                            showEnergy: showEnergy,
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
        .frame(width: 420)
    }

    private var columnHeaders: some View {
        HStack(spacing: 8) {
            // Icon spacer
            Spacer().frame(width: 18)

            // Name (not sortable — just a label)
            Text("Process")
                .font(.system(.caption2, design: .default).weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // CPU header
            sortableHeader("CPU", column: .cpu, width: 50)

            // Energy header
            if showEnergy {
                sortableHeader("Energy", column: .energy, width: 46)
            }

            // RAM header
            sortableHeader("RAM", column: .ram, width: 38)

            // Sparkline spacer
            Spacer().frame(width: 36)

            // Action button spacer
            Spacer().frame(width: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func sortableHeader(_ label: String, column: SortColumn, width: CGFloat) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = false  // Default to descending (highest first)
            }
        } label: {
            HStack(spacing: 2) {
                Text(label)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
            .font(.system(.caption2, design: .default).weight(.medium))
            .foregroundStyle(sortColumn == column ? .primary : .tertiary)
        }
        .buttonStyle(.borderless)
        .frame(width: width, alignment: .trailing)
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
