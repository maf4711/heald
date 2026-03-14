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
            VStack(spacing: 20) {
                // Stats
                HStack(spacing: 20) {
                    FixStat(value: "\(stats.total)", label: "Total Fixes", color: Theme.textPrimary, icon: "wrench.and.screwdriver")
                    FixStat(value: "\(stats.ai)", label: "AI-Driven", color: Theme.accentAI, icon: "brain.head.profile.fill")
                    FixStat(value: "\(stats.healed)", label: "Healed", color: Theme.success, icon: "checkmark.seal.fill")
                    FixStat(value: "\(stats.blocked)", label: "Blocked", color: Theme.warning, icon: "hand.raised.fill")

                    Spacer()

                    Toggle("AI only", isOn: $showOnlyAI)
                        .toggleStyle(.switch)
                        .tint(Theme.accentAI)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(Theme.paddingLG)
                .background(Theme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

                // Fixes
                if fixes.isEmpty {
                    VStack(spacing: Theme.paddingMD) {
                        Image(systemName: "brain.head.profile.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accentAI.opacity(0.2))
                        Text("No AI fixes yet")
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Automated fixes will appear here")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(spacing: 0) {
                        // Table Header
                        HStack(spacing: 0) {
                            Text("STATUS")
                                .frame(width: 30, alignment: .leading)
                            Text("EVENT")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("TYPE")
                                .frame(width: 140, alignment: .leading)
                            Text("TIME")
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, Theme.paddingLG)
                        .padding(.vertical, 10)
                        .background(Theme.surfacePrimary)

                        Rectangle().fill(Theme.cardBorder).frame(height: 0.5)

                        ForEach(fixes) { event in
                            FixRow(event: event)
                            Rectangle().fill(Theme.cardBorder.opacity(0.5)).frame(height: 0.5)
                        }
                    }
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
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
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.1))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
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
        default: return "brain.head.profile.fill"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: statusIcon)
                .font(.system(size: 13))
                .foregroundStyle(statusColor)
                .shadow(color: statusColor.opacity(0.3), radius: 3)
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
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.accentAIDim)
                            .foregroundStyle(Theme.accentAI)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
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
        .padding(.vertical, 9)
        .background(isHovered ? Theme.cardBorder.opacity(0.2) : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
