import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case journal = "Journal"
    case aiFixes = "AI Fixes"
    case health = "Health"
    case processes = "Processes"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .journal: return "list.bullet.rectangle"
        case .aiFixes: return "brain"
        case .health: return "heart.text.clipboard"
        case .processes: return "cpu"
        }
    }
}

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @State private var selectedItem: SidebarItem = .dashboard
    @State private var selectedMachine: Machine?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            if appState.machines.isEmpty {
                await appState.refresh()
            }
            appState.startAutoRefresh()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedItem) {
            Section("Monitor") {
                ForEach([SidebarItem.dashboard, .journal, .aiFixes, .health, .processes]) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
            }

            Section("Machines") {
                ForEach(appState.machines) { machine in
                    Button {
                        selectedMachine = machine
                        selectedItem = .dashboard
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Theme.statusColor(machine.status))
                                .frame(width: 7, height: 7)
                            Text(machine.hostname)
                                .font(.subheadline)
                            Spacer()
                            Text("\(machine.cpu.overallPercent)%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                if let last = appState.lastRefresh {
                    HStack {
                        Text("Updated")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                        Text(last, format: .dateTime.hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                if let error = appState.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(Theme.critical)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.critical)
                            .lineLimit(2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let machine = selectedMachine {
            MacMachineDetailView(machine: machine, history: appState.machineHistory[machine.machineId])
                .id(machine.machineId)
        } else {
            switch selectedItem {
            case .dashboard: MacDashboardView(onSelectMachine: { selectedMachine = $0 })
            case .journal: MacJournalView()
            case .aiFixes: MacAIFixesView()
            case .health: MacHealthView()
            case .processes: MacProcessesView()
            }
        }
    }
}
