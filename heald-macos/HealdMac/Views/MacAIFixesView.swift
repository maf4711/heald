import SwiftUI

struct MacAIFixesView: View {
    @Environment(AppState.self) private var appState
    @State private var showOnlyAI = false

    private var fixes: [ActivityEvent] {
        if showOnlyAI {
            return appState.events.filter { $0.aiGenerated }
        }
        return appState.aiFixEvents
    }

    private var stats: (total: Int, ai: Int, healed: Int, blocked: Int) {
        let all = appState.aiFixEvents
        return (
            total: all.count,
            ai: all.filter { $0.aiGenerated }.count,
            healed: all.filter { $0.type == "healingSuccess" || $0.type == "selfHealed" }.count,
            blocked: all.filter { $0.type == "aiFixBlocked" }.count
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.paddingLG) {
                // Stats
                HStack(spacing: Theme.paddingLG) {
                    FixStat(value: "\(stats.total)", label: "Total Fixes", color: Theme.textPrimary)
                    FixStat(value: "\(stats.ai)", label: "AI-Driven", color: Theme.accentAI)
                    FixStat(value: "\(stats.healed)", label: "Healed", color: Theme.success)
                    FixStat(value: "\(stats.blocked)", label: "Blocked", color: Theme.warning)

                    Spacer()

                    Toggle("AI only", isOn: $showOnlyAI)
                        .toggleStyle(.switch)
                        .tint(Theme.accentAI)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Fixes
                if fixes.isEmpty {
                    VStack(spacing: Theme.paddingMD) {
                        Image(systemName: "brain")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accentAI.opacity(0.3))
                        Text("No AI fixes yet")
                            .font(.headline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 0) {
                        // Table Header
                        HStack(spacing: 0) {
                            Text("Status")
                                .frame(width: 30, alignment: .leading)
                            Text("Event")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Type")
                                .frame(width: 140, alignment: .leading)
                            Text("Time")
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, Theme.paddingLG)
                        .padding(.vertical, Theme.paddingSM)

                        Divider().background(Theme.cardBorder)

                        ForEach(fixes) { event in
                            FixRow(event: event)
                            Divider().background(Theme.cardBorder)
                        }
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius)
                            .stroke(Theme.cardBorder, lineWidth: 0.5)
                    )
                }
            }
            .padding(Theme.paddingXL)
        }
        .background(Theme.background)
    }
}

struct FixStat: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

struct FixRow: View {
    let event: ActivityEvent
    @State private var isHovered = false

    private var statusColor: Color {
        switch event.type {
        case "healingSuccess", "selfHealed": return Theme.success
        case "healingFailed", "aiFixBlocked": return Theme.critical
        case "healingAttempt": return Theme.warning
        default: return Theme.accentAI
        }
    }

    private var statusIcon: String {
        switch event.type {
        case "healingSuccess", "selfHealed": return "checkmark.circle.fill"
        case "healingFailed": return "xmark.circle.fill"
        case "aiFixBlocked": return "hand.raised.fill"
        case "healingAttempt": return "arrow.triangle.2.circlepath"
        default: return "brain"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: statusIcon)
                .font(.system(size: 12))
                .foregroundStyle(statusColor)
                .frame(width: 30, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(event.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if event.aiGenerated {
                        Text("AI")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.accentAI.opacity(0.15))
                            .foregroundStyle(Theme.accentAI)
                            .clipShape(Capsule())
                    }
                }
                if isHovered, let detail = event.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(event.type)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 140, alignment: .leading)

            Text(event.timestampFormatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, Theme.paddingLG)
        .padding(.vertical, Theme.paddingSM)
        .background(isHovered ? Theme.cardBorder.opacity(0.3) : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
