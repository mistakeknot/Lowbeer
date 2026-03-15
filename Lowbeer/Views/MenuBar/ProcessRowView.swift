import SwiftUI

struct ProcessRowView: View {
    let process: ProcessInfo
    let systemWatts: Double
    let totalCPU: Double
    let onThrottle: () -> Void
    let onResume: () -> Void

    private var cpuColor: Color {
        if process.cpuPercent > 80 { return .red }
        if process.cpuPercent > 40 { return .orange }
        return .blue
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0fM", mb)
    }

    private func memoryColor(_ bytes: UInt64) -> Color {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 10 { return .red }
        if gb >= 2 { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            // App icon
            if let icon = process.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "app")
                    .frame(width: 18, height: 18)
            }

            // Process name
            Text(process.name)
                .font(.system(.body, design: .default))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // CPU %
            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(cpuColor)
                .frame(width: 50, alignment: .trailing)

            // Energy share (% of system power)
            if systemWatts >= PowerSample.displayThreshold, totalCPU > 0 {
                let share = (process.cpuPercent / totalCPU) * 100.0
                Text(String(format: "%.0f%%⚡", share))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }

            // Memory (compact: 142M or 1.2G)
            Text(formatMemory(process.residentBytes))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(memoryColor(process.residentBytes))
                .frame(width: 38, alignment: .trailing)

            // Sparkline
            SparklineView(
                samples: process.history.samples,
                color: cpuColor
            )

            // Throttle/Resume button
            if process.isThrottled {
                Button(action: onResume) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Resume process")
            } else if process.cpuPercent > 10 {
                Button(action: onThrottle) {
                    Image(systemName: "pause.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Stop process")
            } else {
                Spacer()
                    .frame(width: 20)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(process.isThrottled ? Color.orange.opacity(0.08) : Color.clear)
        .cornerRadius(4)
    }
}
