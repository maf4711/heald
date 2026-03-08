import SwiftUI

struct StatusBadge: View {
    let status: StatusLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Theme.statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.rawValue.capitalized)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.statusColor(status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.statusColor(status).opacity(0.12))
        .clipShape(Capsule())
    }
}

struct MiniChart: View {
    let data: [Double]
    var color: Color = Theme.accent
    var height: CGFloat = 40

    var body: some View {
        GeometryReader { geo in
            let maxVal = max(data.max() ?? 1, 0.01)
            let step = geo.size.width / CGFloat(max(data.count - 1, 1))

            Path { path in
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * step
                    let y = geo.size.height - (CGFloat(value / maxVal) * geo.size.height)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Gradient fill
            Path { path in
                for (index, value) in data.enumerated() {
                    let x = CGFloat(index) * step
                    let y = geo.size.height - (CGFloat(value / maxVal) * geo.size.height)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: geo.size.height))
                        path.addLine(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                path.addLine(to: CGPoint(x: CGFloat(data.count - 1) * step, y: geo.size.height))
                path.closeSubpath()
            }
            .fill(
                LinearGradient(
                    colors: [color.opacity(0.3), color.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(height: height)
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 2)
                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                    .opacity(isPulsing ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            )
            .onAppear { isPulsing = true }
    }
}
