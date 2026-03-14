import SwiftUI

struct MacProcessesView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedMachineId: String?
    @State private var sortMode: ProcSort = .cpu

    private var currentMachine: Machine? {
        if let id = selectedMachineId {
            return appState.machines.first { $0.machineId == id }
        }
        return appState.machines.first
    }

    private var processes: [ProcessInfo] {
        guard let machine = currentMachine else { return [] }
        return sortMode == .cpu ? machine.processes.topCPU : machine.processes.topRAM
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: Theme.paddingLG) {
                // Machine Picker
                if appState.machines.count > 1 {
                    Picker("Machine", selection: Binding(
                        get: { selectedMachineId ?? appState.machines.first?.machineId ?? "" },
                        set: { selectedMachineId = $0 }
                    )) {
                        ForEach(appState.machines) { machine in
                            Text(machine.hostname).tag(machine.machineId)
                        }
                    }
                    .frame(width: 200)
                } else if let machine = currentMachine {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.statusColor(machine.status))
                            .frame(width: 7, height: 7)
                            .shadow(color: Theme.statusColor(machine.status).opacity(0.5), radius: 3)
                        Text(machine.hostname)
                            .font(.system(.subheadline, design: .default, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }

                Spacer()

                Picker("Sort", selection: $sortMode) {
                    Text("CPU").tag(ProcSort.cpu)
                    Text("RAM").tag(ProcSort.ram)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            .padding(.horizontal, Theme.paddingXL)
            .padding(.vertical, Theme.paddingMD)
            .background(Theme.surfacePrimary)

            Rectangle().fill(Theme.cardBorder).frame(height: 0.5)

            if processes.isEmpty {
                Spacer()
                VStack(spacing: Theme.paddingMD) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No process data")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            } else {
                // Table
                VStack(spacing: 0) {
                    // Header
                    HStack(spacing: 0) {
                        Text("#").frame(width: 30, alignment: .leading)
                        Text("PROCESS").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PID").frame(width: 60, alignment: .trailing)
                        Text("CPU").frame(width: 80, alignment: .trailing)
                        Text("RAM").frame(width: 80, alignment: .trailing)
                        Text("TYPE").frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, Theme.paddingXL)
                    .padding(.vertical, 10)
                    .background(Theme.surfacePrimary)

                    Rectangle().fill(Theme.cardBorder).frame(height: 0.5)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(processes.enumerated()), id: \.element.id) { idx, proc in
                                ProcTableRow(process: proc, rank: idx + 1, sortMode: sortMode)
                                Rectangle().fill(Theme.cardBorder.opacity(0.4)).frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
        .background(Theme.background)
    }
}

private enum ProcSort {
    case cpu, ram
}

private struct ProcTableRow: View {
    let process: ProcessInfo
    let rank: Int
    let sortMode: ProcSort
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 30, alignment: .leading)

            HStack(spacing: 6) {
                Text(process.name)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if process.system {
                    Text("SYS")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.accentAI.opacity(0.1))
                        .foregroundStyle(Theme.accentAI)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(process.pid)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 60, alignment: .trailing)

            Text(String(format: "%.1f%%", process.cpuPercent))
                .font(.subheadline.monospacedDigit().weight(sortMode == .cpu ? .semibold : .regular))
                .foregroundStyle(sortMode == .cpu ? cpuColor : Theme.textSecondary)
                .frame(width: 80, alignment: .trailing)

            Text(String(format: "%.0f MB", process.ramMB))
                .font(.subheadline.monospacedDigit().weight(sortMode == .ram ? .semibold : .regular))
                .foregroundStyle(sortMode == .ram ? ramColor : Theme.textSecondary)
                .frame(width: 80, alignment: .trailing)

            Text(process.system ? "System" : "User")
                .font(.caption)
                .foregroundStyle(process.system ? Theme.accentAI : Theme.textTertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, Theme.paddingXL)
        .padding(.vertical, 8)
        .background(isHovered ? Theme.cardBorder.opacity(0.2) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Theme.critical
        case 2: return Theme.warning
        case 3: return Theme.accent
        default: return Theme.textTertiary
        }
    }

    private var cpuColor: Color {
        if process.cpuPercent > 80 { return Theme.critical }
        if process.cpuPercent > 50 { return Theme.warning }
        return Theme.accent
    }

    private var ramColor: Color {
        if process.ramMB > 2000 { return Theme.critical }
        if process.ramMB > 1000 { return Theme.warning }
        return Theme.accent
    }
}
