import SwiftUI

struct ProcessRowView: View {
    let process: ProcessInfo
    let onThrottle: () -> Void
    let onResume: () -> Void

    private var cpuColor: Color {
        if process.cpuPercent > 80 { return .red }
        if process.cpuPercent > 40 { return .orange }
        return .blue
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
            Text(String(format: "%.0f%%", process.cpuPercent))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(cpuColor)
                .frame(width: 44, alignment: .trailing)

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
