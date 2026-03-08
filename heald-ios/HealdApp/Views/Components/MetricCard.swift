import SwiftUI

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var subtitle: String? = nil
    var color: Color = Theme.accent
    var progress: Double? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingSM) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if let progress {
                ProgressView(value: min(progress, 1.0))
                    .tint(progressColor(progress))
                    .scaleEffect(y: 1.5)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func progressColor(_ value: Double) -> Color {
        if value > 0.9 { return Theme.critical }
        if value > 0.75 { return Theme.warning }
        return color
    }
}

// MARK: - Compact Metric

struct MetricRow: View {
    let label: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
