import SwiftUI

struct AIFixesView: View {
    @Environment(AppState.self) private var appState
    @State private var showOnlyAI = false

    private var fixes: [ActivityEvent] {
        if showOnlyAI {
            return appState.events.filter { $0.aiGenerated }
        }
        return appState.aiFixEvents
    }

    private var stats: FixStats {
        let all = appState.aiFixEvents
        return FixStats(
            total: all.count,
            aiDriven: all.filter { $0.aiGenerated }.count,
            healed: all.filter { $0.type == "healingSuccess" || $0.type == "selfHealed" }.count,
            blocked: all.filter { $0.type == "aiFixBlocked" }.count
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.paddingLG) {
                    // Stats
                    statsGrid

                    // Toggle
                    HStack {
                        Text("AI-driven only")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Toggle("", isOn: $showOnlyAI)
                            .tint(Theme.accentAI)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 4)

                    // Fixes List
                    if fixes.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(fixes) { event in
                                AIFixRow(event: event)
                                if event.id != fixes.last?.id {
                                    Divider()
                                        .background(Theme.cardBorder)
                                        .padding(.leading, 48)
                                }
                            }
                        }
                        .cardStyle()
                    }
                }
                .padding(.horizontal, Theme.paddingLG)
                .padding(.bottom, Theme.paddingXL)
            }
            .background(Theme.background)
            .navigationTitle("AI Fixes")
            .refreshable {
                await appState.refresh()
            }
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: Theme.paddingSM) {
            StatCard(value: "\(stats.total)", label: "Total", color: Theme.textPrimary)
            StatCard(value: "\(stats.aiDriven)", label: "AI", color: Theme.accentAI)
            StatCard(value: "\(stats.healed)", label: "Healed", color: Theme.success)
            StatCard(value: "\(stats.blocked)", label: "Blocked", color: Theme.warning)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.paddingMD) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accentAI.opacity(0.3))
            Text("No AI fixes yet")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("AI-driven healing actions will appear here")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Stats

private struct FixStats {
    let total: Int
    let aiDriven: Int
    let healed: Int
    let blocked: Int
}

struct StatCard: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - AI Fix Row

struct AIFixRow: View {
    let event: ActivityEvent
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: Theme.paddingMD) {
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: statusIcon)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(statusColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.summary)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: Theme.paddingSM) {
                            Text(event.timestampFormatted)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textTertiary)

                            if event.aiGenerated {
                                AIBadge()
                            }

                            Text(event.type)
                                .font(.caption2.monospaced())
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, Theme.paddingSM)
            }
            .buttonStyle(.plain)

            if isExpanded, let detail = event.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, 48)
                    .padding(.bottom, Theme.paddingSM)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

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
        case "healingSuccess", "selfHealed": return "checkmark.circle"
        case "healingFailed": return "xmark.circle"
        case "aiFixBlocked": return "hand.raised"
        case "healingAttempt": return "arrow.triangle.2.circlepath"
        default: return "brain"
        }
    }
}
