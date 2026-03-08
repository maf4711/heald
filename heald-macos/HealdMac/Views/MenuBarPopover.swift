import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text("Heald")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if appState.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Theme.accent)
                }
                StatusDot(status: appState.worstStatus)
            }
            .padding(Theme.paddingLG)
            .background(Theme.cardBackground)

            Divider().background(Theme.cardBorder)

            if !appState.isConfigured {
                unconfiguredView
            } else {
                // Machine List
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(appState.machines) { machine in
                            PopoverMachineRow(machine: machine)
                        }

                        if appState.machines.isEmpty && !appState.isLoading {
                            Text("No machines connected")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.vertical, Theme.paddingXL)
                        }
                    }
                }
                .frame(maxHeight: 300)

                // Recent Events
                if !appState.events.isEmpty {
                    Divider().background(Theme.cardBorder)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recent")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, Theme.paddingLG)
                            .padding(.top, Theme.paddingSM)

                        ForEach(appState.events.prefix(3)) { event in
                            PopoverEventRow(event: event)
                        }
                    }
                    .padding(.bottom, Theme.paddingSM)
                }
            }

            Divider().background(Theme.cardBorder)

            // Footer
            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .font(.subheadline.weight(.medium))

                Spacer()

                if let last = appState.lastRefresh {
                    Text(last, format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }

                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.paddingLG)
            .padding(.vertical, Theme.paddingMD)
            .background(Theme.cardBackground)
        }
        .frame(width: 340)
        .background(Theme.background)
        .task {
            await appState.refresh()
            appState.startAutoRefresh()
        }
    }

    private var unconfiguredView: some View {
        VStack(spacing: Theme.paddingMD) {
            Image(systemName: "key")
                .font(.title)
                .foregroundStyle(Theme.textTertiary)
            Text("Not configured")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Text("Open Settings to add your API key")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.paddingXL)
    }
}

// MARK: - Popover Machine Row

struct PopoverMachineRow: View {
    let machine: Machine

    var body: some View {
        HStack(spacing: Theme.paddingMD) {
            StatusDot(status: machine.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.hostname)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(machine.lastSeenFormatted)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            HStack(spacing: Theme.paddingMD) {
                MiniStat(label: "CPU", value: "\(machine.cpu.overallPercent)%",
                         color: machine.cpu.overall > 0.8 ? Theme.warning : Theme.textSecondary)
                MiniStat(label: "RAM", value: String(format: "%.1f", machine.ram.usedGB),
                         color: machine.ram.pressureLevel >= 2 ? Theme.warning : Theme.textSecondary)
            }
        }
        .padding(.horizontal, Theme.paddingLG)
        .padding(.vertical, Theme.paddingSM)
        .background(Theme.background)
    }
}

struct MiniStat: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

struct StatusDot: View {
    let status: StatusLevel

    var body: some View {
        Circle()
            .fill(Theme.statusColor(status))
            .frame(width: 8, height: 8)
    }
}

// MARK: - Popover Event Row

struct PopoverEventRow: View {
    let event: ActivityEvent

    var body: some View {
        HStack(spacing: Theme.paddingSM) {
            Image(systemName: event.icon)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 16)

            Text(event.summary)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Spacer()

            if event.aiGenerated {
                Text("AI")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.accentAI)
            }

            Text(event.timestampFormatted)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.paddingLG)
        .padding(.vertical, 3)
    }
}
