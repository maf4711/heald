import SwiftUI

struct MacDashboardView: View {
    @Environment(AppState.self) private var appState
    var onSelectMachine: (Machine) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.paddingLG) {
                // Status Bar
                HStack(spacing: Theme.paddingLG) {
                    StatusCounter(count: appState.healthyCount, label: "Healthy", color: Theme.success)
                    StatusCounter(count: appState.warningCount, label: "Warning", color: Theme.warning)
                    StatusCounter(count: appState.criticalCount, label: "Critical", color: Theme.critical)
                    StatusCounter(count: appState.offlineCount, label: "Offline", color: Theme.textTertiary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(appState.machines.count) machines")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(appState.events.count) events")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                // Machine Grid
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Theme.paddingLG),
                    GridItem(.flexible(), spacing: Theme.paddingLG),
                ], spacing: Theme.paddingLG) {
                    ForEach(appState.machines.sorted(by: { statusPriority($0.status) < statusPriority($1.status) })) { machine in
                        Button {
                            onSelectMachine(machine)
                        } label: {
                            MacMachineCard(
                                machine: machine,
                                history: appState.machineHistory[machine.machineId]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Recent Activity
                if !appState.events.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        Text("Recent Activity")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)

                        ForEach(appState.events.prefix(8)) { event in
                            MacEventRow(event: event)
                            if event.id != appState.events.prefix(8).last?.id {
                                Divider().background(Theme.cardBorder)
                            }
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(Theme.paddingXL)
        }
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
        HStack(spacing: 8) {
            Circle()
                .fill(count > 0 ? color : Theme.textTertiary)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(count > 0 ? color : Theme.textTertiary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

// MARK: - Machine Card

struct MacMachineCard: View {
    let machine: Machine
    let history: [MetricSnapshot]?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(machine.hostname)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text(machine.lastSeenFormatted)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                StatusPill(status: machine.status)
            }

            HStack(spacing: Theme.paddingLG) {
                MetricGauge(label: "CPU", value: machine.cpu.overall, text: "\(machine.cpu.overallPercent)%")
                MetricGauge(label: "RAM", value: nil, text: String(format: "%.1f GB", machine.ram.usedGB))
                if let vol = machine.disk.volumes.first {
                    MetricGauge(label: "Disk", value: vol.usedPercent, text: String(format: "%.0f GB free", vol.freeGB))
                }
            }

            if let history, !history.isEmpty {
                MiniChart(data: history.suffix(30).map { $0.cpuOverall }, color: Theme.accent, height: 36)
            }
        }
        .cardStyle()
    }
}

struct MetricGauge: View {
    let label: String
    let value: Double?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let value {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.cardBorder).frame(height: 3)
                        Capsule().fill(gaugeColor(value)).frame(width: geo.size.width * min(value, 1.0), height: 3)
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private func gaugeColor(_ v: Double) -> Color {
        if v > 0.9 { return Theme.critical }
        if v > 0.75 { return Theme.warning }
        return Theme.accent
    }
}

struct StatusPill: View {
    let status: StatusLevel

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Theme.statusColor(status)).frame(width: 6, height: 6)
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

// MARK: - Mini Chart

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
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

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
            .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
        }
        .frame(height: height)
    }
}

// MARK: - Event Row

struct MacEventRow: View {
    let event: ActivityEvent

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

    var body: some View {
        HStack(spacing: Theme.paddingMD) {
            Image(systemName: event.icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 20)

            Text(event.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            if event.aiGenerated {
                Text("AI")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.accentAI.opacity(0.15))
                    .foregroundStyle(Theme.accentAI)
                    .clipShape(Capsule())
            }

            Text(event.category.label)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(iconColor.opacity(0.1))
                .foregroundStyle(iconColor)
                .clipShape(Capsule())

            Text(event.timestampFormatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
