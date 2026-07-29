import SwiftUI

struct MachineDetailView: View {
    let machine: Machine
    let history: [MetricSnapshot]?

    @Environment(AppState.self) private var appState

    var machineEvents: [ActivityEvent] {
        appState.events.filter { $0.machineId == machine.machineId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.paddingLG) {
                // Header
                header

                // CPU
                cpuSection

                // RAM
                ramSection

                // Disk
                diskSection

                // iCloud
                if machine.icloud != nil {
                    icloudSection
                }

                // Processes
                processSection

                // Recent Events
                if !machineEvents.isEmpty {
                    eventsSection
                }
            }
            .padding(.horizontal, Theme.paddingLG)
            .padding(.bottom, Theme.paddingXL)
        }
        .background(Theme.background)
        .navigationTitle(machine.hostname)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    PulsingDot(color: Theme.statusColor(machine.status))
                    Text(machine.status.rawValue.capitalized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.statusColor(machine.status))
                }
                Text("Last seen \(machine.lastSeenFormatted)")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text(machine.machineId)
                .font(.caption.monospaced())
                .foregroundStyle(Theme.textTertiary)
        }
        .cardStyle()
    }

    // MARK: - CPU

    private var cpuSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "CPU", icon: "cpu", value: "\(machine.cpu.overallPercent)%")

            if let history, !history.isEmpty {
                MiniChart(
                    data: history.map { $0.cpuUnit },
                    color: Theme.accent,
                    height: 60
                )
            }

            if !machine.cpu.perCore.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: min(machine.cpu.perCore.count, 8)), spacing: 4) {
                    ForEach(Array(machine.cpu.perCore.enumerated()), id: \.offset) { index, value in
                        let unit = machine.cpu.coreUnit(value)
                        VStack(spacing: 2) {
                            Text("\(Int(unit * 100))")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(coreColor(unit))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(coreColor(unit).opacity(0.3))
                                .frame(height: 3)
                                .overlay(alignment: .leading) {
                                    GeometryReader { geo in
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(coreColor(unit))
                                            .frame(width: geo.size.width * unit)
                                    }
                                }
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - RAM

    private var ramSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(
                title: "Memory",
                icon: "memorychip",
                value: String(format: "%.1f GB", machine.ram.usedGB)
            )

            if let history, !history.isEmpty {
                MiniChart(
                    data: history.map { $0.ramUsedGB },
                    color: Theme.accentAI,
                    height: 60
                )
            }

            VStack(spacing: 6) {
                MetricRow(label: "Wired", value: String(format: "%.1f GB", machine.ram.wiredGB))
                MetricRow(label: "Compressed", value: String(format: "%.1f GB", machine.ram.compressedGB))
                MetricRow(label: "Swap", value: String(format: "%.0f MB", machine.ram.swapUsedMB),
                          color: machine.ram.swapUsedMB > 100 ? Theme.warning : Theme.textPrimary)
                MetricRow(label: "Pressure", value: machine.ram.pressureText,
                          color: machine.ram.pressureLevel >= 4 ? Theme.critical :
                                 machine.ram.pressureLevel >= 2 ? Theme.warning : Theme.success)
            }
        }
        .cardStyle()
    }

    // MARK: - Disk

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "Storage", icon: "internaldrive", value: "")

            ForEach(machine.disk.volumes) { vol in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(vol.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(String(format: "%.0f / %.0f GB", vol.usedGB, vol.totalGB))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ProgressView(value: vol.usedPercent)
                        .tint(vol.usedPercent > 0.9 ? Theme.critical :
                              vol.usedPercent > 0.75 ? Theme.warning : Theme.accent)
                        .scaleEffect(y: 1.5)
                }
            }

            if !machine.disk.smart.isEmpty {
                Divider().background(Theme.cardBorder)
                ForEach(machine.disk.smart) { smart in
                    HStack {
                        Image(systemName: smart.isHealthy ? "checkmark.shield" : "exclamationmark.shield")
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
    }

    // MARK: - iCloud

    private var icloudSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "iCloud Drive", icon: "icloud", value: machine.icloud.map { "\(Int($0.syncPercent))%" } ?? "")
            if let ic = machine.icloud {
                VStack(spacing: 6) {
                    MetricRow(label: "Sync", value: "\(Int(ic.syncPercent))%")
                    MetricRow(label: "Local files", value: "\(ic.localFiles)")
                    MetricRow(label: "Cloud only", value: "\(ic.cloudFiles)")
                    MetricRow(label: "Docs size", value: String(format: "%.1f GB", ic.docsSizeGB))
                    MetricRow(label: "Conflicts", value: "\(ic.conflicts)",
                              color: ic.conflicts > 0 ? Theme.warning : Theme.textPrimary)
                    MetricRow(label: "bird", value: ic.birdRunning ? "running" : "stopped",
                              color: ic.birdRunning ? Theme.success : Theme.critical)
                }
                ProgressView(value: min(ic.syncPercent / 100, 1))
                    .tint(Theme.accentAI)
                    .scaleEffect(y: 1.5)
            }
        }
        .cardStyle()
    }

    // MARK: - Processes

    private var processSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "Top Processes", icon: "list.number", value: "")

            ProcessList(title: "By CPU", processes: machine.processes.topCPU.prefix(5).map { $0 }, metric: .cpu)

            if !machine.processes.topRAM.isEmpty {
                Divider().background(Theme.cardBorder)
                ProcessList(title: "By RAM", processes: machine.processes.topRAM.prefix(5).map { $0 }, metric: .ram)
            }
        }
        .cardStyle()
    }

    // MARK: - Events

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: Theme.paddingMD) {
            SectionHeader(title: "Recent Events", icon: "clock.arrow.circlepath", value: "\(machineEvents.count)")

            ForEach(machineEvents.prefix(10)) { event in
                EventRow(event: event)
                if event.id != machineEvents.prefix(10).last?.id {
                    Divider().background(Theme.cardBorder)
                }
            }
        }
        .cardStyle()
    }

    private func coreColor(_ value: Double) -> Color {
        if value > 0.9 { return Theme.critical }
        if value > 0.7 { return Theme.warning }
        return Theme.accent
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String
    let value: String

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if !value.isEmpty {
                Text(value)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

// MARK: - Process List

enum ProcessMetricType {
    case cpu, ram
}

struct ProcessList: View {
    let title: String
    let processes: [HealdProcess]
    let metric: ProcessMetricType

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textTertiary)

            ForEach(processes) { proc in
                HStack(spacing: Theme.paddingSM) {
                    Text(proc.name)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if proc.system {
                        Text("SYS")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.textTertiary.opacity(0.2))
                            .foregroundStyle(Theme.textTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer()
                    switch metric {
                    case .cpu:
                        Text(String(format: "%.1f%%", proc.cpuPercent))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(proc.cpuPercent > 80 ? Theme.critical :
                                             proc.cpuPercent > 50 ? Theme.warning : Theme.textSecondary)
                    case .ram:
                        Text(String(format: "%.0f MB", proc.ramMB))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}
