import SwiftUI

/// A tiny line chart showing CPU history for a process.
struct SparklineView: View {
    let samples: [Double]
    let maxValue: Double
    var color: Color = .blue

    init(samples: [Double], maxValue: Double = 100, color: Color = .blue) {
        self.samples = samples
        self.maxValue = max(maxValue, 1)
        self.color = color
    }

    var body: some View {
        Canvas { context, size in
            guard samples.count >= 2 else { return }

            let stepX = size.width / CGFloat(max(samples.count - 1, 1))
            let scaleY = size.height / CGFloat(maxValue)

            var path = Path()
            for (i, sample) in samples.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height - CGFloat(min(sample, maxValue)) * scaleY
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Fill under the line
            var fillPath = path
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.addLine(to: CGPoint(x: 0, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(color.opacity(0.15)))

            // Stroke the line
            context.stroke(path, with: .color(color.opacity(0.7)), lineWidth: 1)
        }
        .frame(width: 60, height: 16)
    }
}
