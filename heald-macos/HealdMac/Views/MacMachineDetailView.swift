import SwiftUI

struct MacMachineDetailView: View {
    let machine: Machine
    let history: [MetricSnapshot]?

    @Environment(AppState.self) private var appState

    private var machineEvents: [ActivityEvent] {
        appState.events.filter { $0.machineId == machine.machineId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(machine.hostname)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 10) {
                            StatusPill(status: machine.status)
                            Text(machine.lastSeenFormatted)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Text(machine.machineId)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.cardBorder.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                    }
                    Spacer()
                }

                // Metrics Grid
                HStack(spacing: Theme.paddingLG) {
                    // CPU
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        HStack {
                            Image(systemName: "cpu.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accent)
                            Text("CPU")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Text("\(machine.cpu.overallPercent)%")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .shadow(color: Theme.accent.opacity(0.3), radius: 8)

                        if let history, !history.isEmpty {
                            MiniChart(data: history.map { $0.cpuOverall }, color: Theme.accent, height: 50)
                        }

                        if !machine.cpu.perCore.isEmpty {
                            coreGrid
                        }
                    }
                    .cardStyle(glow: Theme.accent)

                    // RAM
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        HStack {
                            Image(systemName: "memorychip.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accentAI)
                            Text("Memory")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Text(String(format: "%.1f GB", machine.ram.usedGB))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.accentAI)
                            .shadow(color: Theme.accentAI.opacity(0.3), radius: 8)

                        if let history, !history.isEmpty {
                            MiniChart(data: history.map { $0.ramUsedGB }, color: Theme.accentAI, height: 50)
                        }

                        VStack(spacing: 6) {
                            MetricDetailRow(label: "Wired", value: String(format: "%.1f GB", machine.ram.wiredGB))
                            MetricDetailRow(label: "Compressed", value: String(format: "%.1f GB", machine.ram.compressedGB))
                            MetricDetailRow(label: "Swap", value: String(format: "%.0f MB", machine.ram.swapUsedMB))
                            MetricDetailRow(label: "Pressure", value: machine.ram.pressureText,
                                            color: machine.ram.pressureLevel >= 4 ? Theme.critical :
                                                   machine.ram.pressureLevel >= 2 ? Theme.warning : Theme.success)
                        }
                    }
                    .cardStyle(glow: Theme.accentAI)
                }

                // Disk + Processes
                HStack(alignment: .top, spacing: Theme.paddingLG) {
                    // Storage
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        HStack {
                            Image(systemName: "internaldrive.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.warning)
                            Text("Storage")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        ForEach(machine.disk.volumes) { vol in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(vol.name)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(String(format: "%.0f / %.0f GB", vol.usedGB, vol.totalGB))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Theme.cardBorder).frame(height: 4)
                                        Capsule()
                                            .fill(
                                                LinearGradient(
                                                    colors: [diskColor(vol.usedPercent), diskColor(vol.usedPercent).opacity(0.6)],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geo.size.width * min(vol.usedPercent, 1.0), height: 4)
                                            .shadow(color: diskColor(vol.usedPercent).opacity(0.3), radius: 3, y: 1)
                                    }
                                }
                                .frame(height: 4)
                            }
                        }

                        if !machine.disk.smart.isEmpty {
                            Divider().background(Theme.cardBorder.opacity(0.5))
                            ForEach(machine.disk.smart) { smart in
                                HStack {
                                    Image(systemName: smart.isHealthy ? "checkmark.shield.fill" : "xmark.shield.fill")
                                        .foregroundStyle(smart.isHealthy ? Theme.success : Theme.critical)
                                        .shadow(color: (smart.isHealthy ? Theme.success : Theme.critical).opacity(0.3), radius: 4)
                                    Text(smart.bsdName)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(smart.status)
                                        .font(.caption)
                                        .foregroundStyle(smart.isHealthy ? Theme.success : Theme.critical)
                                }
                            }
                        }
                    }
                    .cardStyle()

                    // Processes
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        HStack {
                            Image(systemName: "list.number")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.critical)
                            Text("Top Processes")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        ForEach(Array(machine.processes.topCPU.prefix(8).enumerated()), id: \.element.id) { idx, proc in
                            HStack(spacing: Theme.paddingSM) {
                                Text("\(idx + 1)")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(idx < 3 ? Theme.critical : Theme.textTertiary)
                                    .frame(width: 16)

                                Text(proc.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)

                                if proc.system {
                                    Text("SYS")
                                        .font(.system(size: 7, weight: .bold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Theme.accentAI.opacity(0.1))
                                        .foregroundStyle(Theme.accentAI)
                                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                }

                                Spacer()

                                Text(String(format: "%.1f%%", proc.cpuPercent))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(proc.cpuPercent > 80 ? Theme.critical :
                                                     proc.cpuPercent > 50 ? Theme.warning : Theme.textSecondary)

                                Text(String(format: "%.0fM", proc.ramMB))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                    .cardStyle()
                }

                // Events
                if !machineEvents.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accentAI)
                            Text("Recent Events")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }

                        ForEach(machineEvents.prefix(10)) { event in
                            MacEventRow(event: event)
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(Theme.paddingXL)
        }
        .background(Theme.background)
    }

    private func diskColor(_ v: Double) -> Color {
        if v > 0.9 { return Theme.critical }
        if v > 0.75 { return Theme.warning }
        return Theme.accent
    }

    private var coreGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: min(machine.cpu.perCore.count, 8)), spacing: 3) {
            ForEach(Array(machine.cpu.perCore.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(coreColor(value))
                    .frame(height: 10)
                    .overlay(
                        Text("\(Int(value * 100))")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    )
                    .shadow(color: coreColor(value).opacity(0.3), radius: 2)
            }
        }
    }

    private func coreColor(_ v: Double) -> Color {
        if v > 0.9 { return Theme.critical }
        if v > 0.7 { return Theme.warning }
        return Theme.accent.opacity(max(v, 0.15))
    }
}

struct MetricDetailRow: View {
    let label: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}
