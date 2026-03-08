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
            VStack(spacing: Theme.paddingLG) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(machine.hostname)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 8) {
                            StatusPill(status: machine.status)
                            Text(machine.lastSeenFormatted)
                                .font(.caption)
                                .foregroundStyle(Theme.textTertiary)
                            Text(machine.machineId)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                }

                // Metrics Grid
                HStack(spacing: Theme.paddingLG) {
                    // CPU
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        Label("CPU", systemImage: "cpu")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(machine.cpu.overallPercent)%")
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.accent)

                        if let history, !history.isEmpty {
                            MiniChart(data: history.map { $0.cpuOverall }, color: Theme.accent, height: 50)
                        }

                        if !machine.cpu.perCore.isEmpty {
                            coreGrid
                        }
                    }
                    .cardStyle()

                    // RAM
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        Label("Memory", systemImage: "memorychip")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(String(format: "%.1f GB", machine.ram.usedGB))
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(Theme.accentAI)

                        if let history, !history.isEmpty {
                            MiniChart(data: history.map { $0.ramUsedGB }, color: Theme.accentAI, height: 50)
                        }

                        VStack(spacing: 4) {
                            MetricDetailRow(label: "Wired", value: String(format: "%.1f GB", machine.ram.wiredGB))
                            MetricDetailRow(label: "Compressed", value: String(format: "%.1f GB", machine.ram.compressedGB))
                            MetricDetailRow(label: "Swap", value: String(format: "%.0f MB", machine.ram.swapUsedMB))
                            MetricDetailRow(label: "Pressure", value: machine.ram.pressureText,
                                            color: machine.ram.pressureLevel >= 4 ? Theme.critical :
                                                   machine.ram.pressureLevel >= 2 ? Theme.warning : Theme.success)
                        }
                    }
                    .cardStyle()
                }

                // Disk + Processes
                HStack(alignment: .top, spacing: Theme.paddingLG) {
                    // Storage
                    VStack(alignment: .leading, spacing: Theme.paddingMD) {
                        Label("Storage", systemImage: "internaldrive")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

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
                                ProgressView(value: vol.usedPercent)
                                    .tint(vol.usedPercent > 0.9 ? Theme.critical :
                                          vol.usedPercent > 0.75 ? Theme.warning : Theme.accent)
                            }
                        }

                        if !machine.disk.smart.isEmpty {
                            Divider().background(Theme.cardBorder)
                            ForEach(machine.disk.smart) { smart in
                                HStack {
                                    Image(systemName: smart.isHealthy ? "checkmark.shield" : "xmark.shield")
                                        .foregroundStyle(smart.isHealthy ? Theme.success : Theme.critical)
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
                        Label("Top Processes", systemImage: "list.number")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        ForEach(Array(machine.processes.topCPU.prefix(8).enumerated()), id: \.element.id) { idx, proc in
                            HStack(spacing: Theme.paddingSM) {
                                Text("\(idx + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(idx < 3 ? Theme.critical : Theme.textTertiary)
                                    .frame(width: 16)

                                Text(proc.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)

                                if proc.system {
                                    Text("SYS")
                                        .font(.system(size: 7, weight: .bold))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 1)
                                        .background(Theme.textTertiary.opacity(0.2))
                                        .foregroundStyle(Theme.textTertiary)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
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
                        Label("Recent Events", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)

                        ForEach(machineEvents.prefix(10)) { event in
                            MacEventRow(event: event)
                        }
                    }
                    .cardStyle()
                }
            }
            .padding(Theme.paddingXL)
        }
    }

    private var coreGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: min(machine.cpu.perCore.count, 8)), spacing: 3) {
            ForEach(Array(machine.cpu.perCore.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(coreColor(value))
                    .frame(height: 8)
                    .overlay(
                        Text("\(Int(value * 100))")
                            .font(.system(size: 7, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    )
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
