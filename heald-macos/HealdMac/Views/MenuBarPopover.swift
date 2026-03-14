import SwiftUI

struct MenuBarPopover: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "shield.checkered")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 6)
                Text("Heald")
                    .font(.system(.headline, design: .rounded, weight: .bold))
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
            .background(Theme.surfacePrimary)

            Rectangle().fill(Theme.cardBorder).frame(height: 0.5)

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
                            VStack(spacing: 8) {
                                Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                                    .font(.title2)
                                    .foregroundStyle(Theme.textTertiary)
                                Text("No machines connected")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.vertical, Theme.paddingXL)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 300)

                // Recent Events
                if !appState.events.isEmpty {
                    Rectangle().fill(Theme.cardBorder).frame(height: 0.5)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RECENT")
                            .font(.system(size: 10, weight: .semibold))
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

            Rectangle().fill(Theme.cardBorder).frame(height: 0.5)

            // Footer
            HStack {
                Button {
                    openWindow(id: "dashboard")
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                        Text("Dashboard")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

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
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.paddingLG)
            .padding(.vertical, Theme.paddingMD)
            .background(Theme.surfacePrimary)
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
            Image(systemName: "key.fill")
                .font(.title)
                .foregroundStyle(Theme.textTertiary)
            Text("Not configured")
                .font(.subheadline.weight(.medium))
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
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Theme.paddingMD) {
            StatusDot(status: machine.status)

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.hostname)
                    .font(.system(.subheadline, design: .default, weight: .medium))
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
        .padding(.vertical, 7)
        .background(isHovered ? Theme.cardBorder.opacity(0.3) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 4)
        .onHover { isHovered = $0 }
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
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
        }
    }
}

struct StatusDot: View {
    let status: StatusLevel

    var body: some View {
        Circle()
            .fill(Theme.statusColor(status))
            .frame(width: 8, height: 8)
            .shadow(color: Theme.statusColor(status).opacity(0.5), radius: 3)
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
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.accentAIDim)
                    .foregroundStyle(Theme.accentAI)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            Text(event.timestampFormatted)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.paddingLG)
        .padding(.vertical, 3)
    }
}
