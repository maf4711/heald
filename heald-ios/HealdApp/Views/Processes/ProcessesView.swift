import SwiftUI

struct ProcessesView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedMachine: Machine?
    @State private var sortBy: ProcessSortMode = .cpu

    private var currentMachine: Machine? {
        selectedMachine ?? appState.machines.first
    }

    private var processes: [ProcessInfo] {
        guard let machine = currentMachine else { return [] }
        switch sortBy {
        case .cpu: return machine.processes.topCPU
        case .ram: return machine.processes.topRAM
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Machine Selector
                if appState.machines.count > 1 {
                    machineSelector
                }

                // Sort Toggle
                Picker("Sort by", selection: $sortBy) {
                    Text("CPU").tag(ProcessSortMode.cpu)
                    Text("RAM").tag(ProcessSortMode.ram)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.paddingLG)
                .padding(.vertical, Theme.paddingMD)

                // Process List
                if processes.isEmpty {
                    Spacer()
                    VStack(spacing: Theme.paddingMD) {
                        Image(systemName: "cpu")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.textTertiary)
                        Text("No process data")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(Array(processes.enumerated()), id: \.element.id) { index, proc in
                            ProcessRow(process: proc, rank: index + 1, sortMode: sortBy)
                                .listRowBackground(Theme.background)
                                .listRowSeparatorTint(Theme.cardBorder)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.background)
            .navigationTitle("Processes")
            .refreshable {
                await appState.refresh()
            }
        }
    }

    private var machineSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.paddingSM) {
                ForEach(appState.machines) { machine in
                    Button {
                        selectedMachine = machine
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.statusColor(machine.status))
                                .frame(width: 6, height: 6)
                            Text(machine.hostname)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(currentMachine?.machineId == machine.machineId ?
                                    Theme.accent.opacity(0.15) : Theme.cardBackground)
                        .foregroundStyle(currentMachine?.machineId == machine.machineId ?
                                         Theme.accent : Theme.textSecondary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, Theme.paddingLG)
            .padding(.top, Theme.paddingSM)
        }
    }
}

enum ProcessSortMode {
    case cpu, ram
}

struct ProcessRow: View {
    let process: ProcessInfo
    let rank: Int
    let sortMode: ProcessSortMode

    var body: some View {
        HStack(spacing: Theme.paddingMD) {
            // Rank
            Text("\(rank)")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(rankColor)
                .frame(width: 24)

            // Process Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(process.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    if process.system {
                        Text("SYSTEM")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.accentAI.opacity(0.15))
                            .foregroundStyle(Theme.accentAI)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text("PID \(process.pid)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            // Metrics
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                    Text(String(format: "%.1f%%", process.cpuPercent))
                        .font(.caption.monospacedDigit().weight(sortMode == .cpu ? .semibold : .regular))
                        .foregroundStyle(sortMode == .cpu ? cpuColor : Theme.textSecondary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "memorychip")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                    Text(String(format: "%.0f MB", process.ramMB))
                        .font(.caption.monospacedDigit().weight(sortMode == .ram ? .semibold : .regular))
                        .foregroundStyle(sortMode == .ram ? ramColor : Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 4)
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
