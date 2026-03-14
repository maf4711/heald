import SwiftUI

struct MacDashboardView: View {
    @Environment(AppState.self) private var appState
    var onSelectMachine: (Machine) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Status Bar
                HStack(spacing: 20) {
                    StatusCounter(count: appState.healthyCount, label: "Healthy", color: Theme.success)
                    StatusCounter(count: appState.warningCount, label: "Warning", color: Theme.warning)
                    StatusCounter(count: appState.criticalCount, label: "Critical", color: Theme.critical)
                    StatusCounter(count: appState.offlineCount, label: "Offline", color: Theme.textTertiary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(appState.machines.count) machines")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(appState.events.count) events")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(Theme.paddingLG)
                .background(Theme.surfacePrimary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))

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
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.accentAI)
                            Text("Recent Activity")
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(appState.events.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.cardBorder)
                                .clipShape(Capsule())
                        }

                        ForEach(appState.events.prefix(8)) { event in
                            MacEventRow(event: event)
                            if event.id != appState.events.prefix(8).last?.id {
                                Divider().background(Theme.cardBorder.opacity(0.5))
                            }
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(Theme.paddingXL)
        }
        .background(Theme.background)
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
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(count > 0 ? color.opacity(0.15) : Theme.cardBorder.opacity(0.3))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(count > 0 ? color : Theme.textTertiary)
                    .frame(width: 8, height: 8)
                    .shadow(color: count > 0 ? color.opacity(0.6) : .clear, radius: 4)
            }
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
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(machine.hostname)
                        .font(.system(.headline, design: .rounded))
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
        .cardStyle(glow: Theme.statusColor(machine.status))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .stroke(isHovered ? Theme.cardBorderHover : .clear, lineWidth: 0.5)
        )
        .scaleEffect(isHovered ? 1.01 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

struct MetricGauge: View {
    let label: String
    let value: Double?
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            if let value {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.cardBorder).frame(height: 3)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [gaugeColor(value), gaugeColor(value).opacity(0.6)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(value, 1.0), height: 3)
                            .shadow(color: gaugeColor(value).opacity(0.3), radius: 3, y: 1)
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
        HStack(spacing: 5) {
            Circle()
                .fill(Theme.statusColor(status))
                .frame(width: 6, height: 6)
                .shadow(color: Theme.statusColor(status).opacity(0.5), radius: 3)
            Text(status.rawValue.capitalized)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.statusColor(status))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.statusColor(status).opacity(0.1))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(Theme.statusColor(status).opacity(0.2), lineWidth: 0.5)
        )
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
            .shadow(color: color.opacity(0.4), radius: 4, y: 2)

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
            .fill(LinearGradient(colors: [color.opacity(0.2), color.opacity(0.0)], startPoint: .top, endPoint: .bottom))
        }
        .frame(height: height)
    }
}

// MARK: - Event Row

struct MacEventRow: View {
    let event: ActivityEvent
    @State private var isHovered = false

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
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconColor.opacity(0.1))
                    .frame(width: 26, height: 26)
                Image(systemName: event.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(iconColor)
            }

            Text(event.summary)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            if event.aiGenerated {
                Text("AI")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.accentAIDim)
                    .foregroundStyle(Theme.accentAI)
                    .clipShape(Capsule())
            }

            Text(event.category.label)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(iconColor.opacity(0.08))
                .foregroundStyle(iconColor)
                .clipShape(Capsule())

            Text(event.timestampFormatted)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isHovered ? Theme.cardBorder.opacity(0.2) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { isHovered = $0 }
    }
}
