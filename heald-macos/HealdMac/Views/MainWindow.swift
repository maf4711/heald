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
        case .dashboard: return "square.grid.2x2.fill"
        case .journal: return "list.bullet.rectangle.fill"
        case .aiFixes: return "brain.head.profile.fill"
        case .health: return "heart.text.clipboard.fill"
        case .processes: return "cpu.fill"
        }
    }
}

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @State private var selectedItem: SidebarItem = .dashboard
    @State private var selectedMachine: Machine?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().background(Theme.cardBorder)
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
        }
        .background(Theme.background)
        .task {
            if appState.machines.isEmpty {
                await appState.refresh()
            }
            appState.startAutoRefresh()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App branding
            HStack(spacing: 10) {
                Image(systemName: "shield.checkered")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 6)
                Text("Heald")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    Task { await appState.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.paddingLG)
            .padding(.top, 20)
            .padding(.bottom, Theme.paddingMD)

            // Navigation items
            VStack(spacing: 2) {
                Text("MONITOR")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.paddingLG)
                    .padding(.bottom, 4)

                ForEach([SidebarItem.dashboard, .journal, .aiFixes, .health, .processes]) { item in
                    SidebarButton(
                        item: item,
                        isSelected: selectedItem == item && selectedMachine == nil
                    ) {
                        selectedItem = item
                        selectedMachine = nil
                    }
                }
            }
            .padding(.bottom, Theme.paddingLG)

            // Machines
            if !appState.machines.isEmpty {
                VStack(spacing: 2) {
                    Text("MACHINES")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.paddingLG)
                        .padding(.bottom, 4)

                    ForEach(appState.machines) { machine in
                        Button {
                            selectedMachine = machine
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Theme.statusColor(machine.status))
                                    .frame(width: 6, height: 6)
                                    .shadow(color: Theme.statusColor(machine.status).opacity(0.5), radius: 4)
                                Text(machine.hostname)
                                    .font(.system(.subheadline, design: .default, weight: .medium))
                                    .foregroundStyle(selectedMachine?.machineId == machine.machineId ? Theme.textPrimary : Theme.textSecondary)
                                Spacer()
                                Text("\(machine.cpu.overallPercent)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(.horizontal, Theme.paddingLG)
                            .padding(.vertical, 7)
                            .background(
                                selectedMachine?.machineId == machine.machineId
                                    ? Theme.accent.opacity(0.08)
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 6)
                    }
                }
            }

            Spacer()

            // Footer
            VStack(spacing: 6) {
                if let error = appState.error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.critical)
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(Theme.critical)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, Theme.paddingLG)
                }

                if let last = appState.lastRefresh {
                    HStack {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 5, height: 5)
                        Text("Updated \(last, format: .dateTime.hour().minute().second())")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.horizontal, Theme.paddingLG)
                }
            }
            .padding(.bottom, Theme.paddingLG)
        }
        .frame(width: 220)
        .background(Theme.surfacePrimary)
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

// MARK: - Sidebar Button

private struct SidebarButton: View {
    let item: SidebarItem
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Theme.accent : Theme.textTertiary)
                    .frame(width: 20)
                Text(item.rawValue)
                    .font(.system(.subheadline, design: .default, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.paddingLG)
            .padding(.vertical, 8)
            .background(
                Group {
                    if isSelected {
                        Theme.accent.opacity(0.1)
                    } else if isHovered {
                        Theme.cardBorder.opacity(0.4)
                    } else {
                        Color.clear
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSM, style: .continuous))
            .overlay(
                HStack {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isSelected ? Theme.accent : .clear)
                        .frame(width: 3, height: 16)
                    Spacer()
                }
                .padding(.leading, 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovered = $0 }
    }
}
