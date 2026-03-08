import SwiftUI

struct EventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: Theme.paddingMD) {
            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: event.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)

                    Spacer()

                    if event.aiGenerated {
                        AIBadge()
                    }
                }

                HStack(spacing: Theme.paddingSM) {
                    Text(event.timestampFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)

                    Text(event.category.label)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(iconColor.opacity(0.12))
                        .foregroundStyle(iconColor)
                        .clipShape(Capsule())
                }

                if let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var iconColor: Color {
        switch event.category {
        case .healing: return Theme.accent
        case .ai: return Theme.accentAI
        case .health: return Theme.warning
        case .maintenance: return Theme.textSecondary
        case .system: return Theme.textTertiary
        case .process: return Theme.critical
        }
    }
}

struct AIBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "brain")
                .font(.system(size: 8))
            Text("AI")
                .font(.system(size: 9, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Theme.accentAI.opacity(0.15))
        .foregroundStyle(Theme.accentAI)
        .clipShape(Capsule())
    }
}
