import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.paddingLG) {
                    // Status Summary
                    statusSummary

                    // Machine Cards
                    if appState.machines.isEmpty && !appState.isLoading {
                        emptyState
                    } else {
                        ForEach(appState.machines.sorted(by: { statusPriority($0.status) < statusPriority($1.status) })) { machine in
                            NavigationLink(value: machine.machineId) {
                                MachineCardView(
                                    machine: machine,
                                    history: appState.machineHistory[machine.machineId]
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Recent Activity
                    if !appState.events.isEmpty {
                        recentActivity
                    }
                }
                .padding(.horizontal, Theme.paddingLG)
                .padding(.bottom, Theme.paddingXL)
            }
            .background(Theme.background)
            .navigationTitle("Heald")
            .navigationDestination(for: String.self) { machineId in
                if let machine = appState.machines.first(where: { $0.machineId == machineId }) {
                    MachineDetailView(
                        machine: machine,
                        history: appState.machineHistory[machineId]
                    )
                }
            }
            .refreshable {
                await appState.refresh()
            }
            .overlay {
                if appState.isLoading && appState.machines.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
        }
    }

    // MARK: - Status Summary

    private var statusSummary: some View {
        HStack(spacing: Theme.paddingMD) {
            StatusCounter(count: appState.healthyCount, label: "Healthy", color: Theme.success)
            StatusCounter(count: appState.warningCount, label: "Warning", color: Theme.warning)
            StatusCounter(count: appState.criticalCount, label: "Critical", color: Theme.critical)
            StatusCounter(count: appState.offlineCount, label: "Offline", color: Theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.paddingMD) {
            Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Theme.textTertiary)
            Text("No machines connected")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)
            Text("Install heald on your Mac to start monitoring")
                .font(.subheadline)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            HStack {
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let last = appState.lastRefresh {
                    Text("Updated \(last, format: .dateTime.hour().minute().second())")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            ForEach(appState.events.prefix(5)) { event in
                EventRow(event: event)
                if event.id != appState.events.prefix(5).last?.id {
                    Divider()
                        .background(Theme.cardBorder)
                }
            }
        }
        .cardStyle()
    }

    private func statusPriority(_ status: StatusLevel) -> Int {
        switch status {
        case .critical: return 0
        case .warning: return 1
        case .healthy: return 2
        case .offline: return 3
        }
    }
}

// MARK: - Status Counter

struct StatusCounter: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(count > 0 ? color : Theme.textTertiary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - Machine Card

struct MachineCardView: View {
    let machine: Machine
    let history: [MetricSnapshot]?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.hostname)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        PulsingDot(color: Theme.statusColor(machine.status))
                        Text(machine.lastSeenFormatted)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                StatusBadge(status: machine.status)
            }

            // Metrics Grid
            HStack(spacing: Theme.paddingSM) {
                MiniMetric(
                    label: "CPU",
                    value: "\(machine.cpu.overallPercent)%",
                    progress: machine.cpu.overall
                )
                MiniMetric(
                    label: "RAM",
                    value: String(format: "%.1fGB", machine.ram.usedGB),
                    progress: nil
                )
                if let vol = machine.disk.volumes.first {
                    MiniMetric(
                        label: "Disk",
                        value: String(format: "%.0fGB", vol.freeGB),
                        progress: vol.usedPercent
                    )
                }
            }

            // Mini Chart
            if let history, !history.isEmpty {
                MiniChart(
                    data: history.suffix(30).map { $0.cpuOverall },
                    color: Theme.accent,
                    height: 32
                )
            }
        }
        .cardStyle()
    }
}

struct MiniMetric: View {
    let label: String
    let value: String
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Theme.cardBorder)
                            .frame(height: 3)
                        Capsule()
                            .fill(progressColor(progress))
                            .frame(width: geo.size.width * min(progress, 1.0), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progressColor(_ value: Double) -> Color {
        if value > 0.9 { return Theme.critical }
        if value > 0.75 { return Theme.warning }
        return Theme.accent
    }
}
