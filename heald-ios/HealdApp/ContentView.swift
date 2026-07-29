import SwiftUI

/// Root shell: iPhone = tabs, iPad = sidebar + detail (universal).
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if !appState.isConfigured {
                SettingsView(isOnboarding: true)
            } else if sizeClass == .regular {
                IPadRootView()
            } else {
                IPhoneRootView()
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - iPhone

struct IPhoneRootView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label("Fleet", systemImage: "square.grid.2x2") }
                .tag(0)
            JournalView()
                .tabItem { Label("Journal", systemImage: "list.bullet.rectangle") }
                .tag(1)
            AIFixesView()
                .tabItem { Label("AI", systemImage: "brain") }
                .tag(2)
            HealthView()
                .tabItem { Label("Health", systemImage: "heart.text.clipboard") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        .overlay { loadingOverlay }
        .task { await bootstrap() }
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if appState.isLoading && appState.machines.isEmpty {
            LoadingOverlay(error: appState.error) {
                Task { await appState.refresh() }
            }
        }
    }

    private func bootstrap() async {
        await appState.refresh()
        appState.startAutoRefresh()
    }
}

// MARK: - iPad

struct IPadRootView: View {
    @Environment(AppState.self) private var appState
    @State private var selection: SidebarItem? = .fleet
    @State private var selectedMachineId: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Monitor") {
                    Label("Fleet", systemImage: "square.grid.2x2")
                        .tag(SidebarItem.fleet)
                    Label("Journal", systemImage: "list.bullet.rectangle")
                        .tag(SidebarItem.journal)
                    Label("AI Fixes", systemImage: "brain")
                        .tag(SidebarItem.ai)
                    Label("Health", systemImage: "heart.text.clipboard")
                        .tag(SidebarItem.health)
                }
                if !appState.machines.isEmpty {
                    Section("Machines") {
                        ForEach(appState.machines.sorted(by: { $0.hostname < $1.hostname })) { machine in
                            HStack {
                                PulsingDot(color: Theme.statusColor(machine.status))
                                Text(machine.hostname)
                                Spacer()
                                Text("\(machine.cpu.overallPercent)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .tag(SidebarItem.machine(machine.machineId))
                        }
                    }
                }
                Section {
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationTitle("Heald")
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                fleetFooter
            }
        } detail: {
            detailContent
                .background(Theme.background)
        }
        .navigationSplitViewStyle(.balanced)
        .overlay { loadingOverlay }
        .task { await bootstrap() }
        .onChange(of: selection) { _, newValue in
            if case .machine(let id) = newValue {
                selectedMachineId = id
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection ?? .fleet {
        case .fleet:
            DashboardView()
        case .journal:
            JournalView()
        case .ai:
            AIFixesView()
        case .health:
            HealthView()
        case .settings:
            SettingsView()
        case .machine(let id):
            if let machine = appState.machines.first(where: { $0.machineId == id }) {
                NavigationStack {
                    MachineDetailView(
                        machine: machine,
                        history: appState.machineHistory[id]
                    )
                }
            } else {
                ContentUnavailableView("Machine offline", systemImage: "desktopcomputer.trianglebadge.exclamationmark")
            }
        }
    }

    private var fleetFooter: some View {
        HStack(spacing: 12) {
            StatusPill(count: appState.healthyCount, color: Theme.success)
            StatusPill(count: appState.warningCount, color: Theme.warning)
            StatusPill(count: appState.criticalCount, color: Theme.critical)
            StatusPill(count: appState.offlineCount, color: Theme.textTertiary)
            Spacer()
            if let last = appState.lastRefresh {
                Text(last, format: .dateTime.hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(12)
        .background(Theme.cardBackground.opacity(0.95))
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if appState.isLoading && appState.machines.isEmpty {
            LoadingOverlay(error: appState.error) {
                Task { await appState.refresh() }
            }
        }
    }

    private func bootstrap() async {
        await appState.refresh()
        appState.startAutoRefresh()
    }
}

// MARK: - Sidebar

enum SidebarItem: Hashable {
    case fleet, journal, ai, health, settings
    case machine(String)
}

// MARK: - Shared chrome

struct LoadingOverlay: View {
    let error: String?
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Lade Fleet…")
                .foregroundStyle(.secondary)
            if let error {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Erneut versuchen", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background.opacity(0.92))
    }
}

struct StatusPill: View {
    let count: Int
    let color: Color

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(count > 0 ? color : Theme.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(count > 0 ? 0.15 : 0.05))
            .clipShape(Capsule())
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
