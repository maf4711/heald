import SwiftUI

/// Keep navigation outside the layout branches so resizing preserves location.
struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var navigation = RootNavigationState()

    var body: some View {
        Group {
            if !appState.isConfigured {
                SettingsView(isOnboarding: true)
            } else if sizeClass == .regular {
                IPadRootView(navigation: $navigation)
            } else {
                IPhoneRootView(navigation: $navigation)
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

// MARK: - iPhone

struct IPhoneRootView: View {
    @Environment(AppState.self) private var appState
    @Binding var navigation: RootNavigationState

    var body: some View {
        TabView(selection: $navigation.tabSelection) {
            DashboardView(path: $navigation.dashboardPath)
                .tabItem { Label("Fleet", systemImage: "square.grid.2x2") }
                .tag(SidebarItem.fleet)
            JournalView()
                .tabItem { Label("Journal", systemImage: "list.bullet.rectangle") }
                .tag(SidebarItem.journal)
            AIFixesView()
                .tabItem { Label("AI", systemImage: "brain") }
                .tag(SidebarItem.ai)
            HealthView()
                .tabItem { Label("Health", systemImage: "heart.text.clipboard") }
                .tag(SidebarItem.health)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(SidebarItem.settings)
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
    @Binding var navigation: RootNavigationState

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.sidebarSelection) {
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
    }

    @ViewBuilder
    private var detailContent: some View {
        switch navigation.section {
        case .fleet, .machine:
            DashboardView(path: $navigation.dashboardPath)
        case .journal:
            JournalView()
        case .ai:
            AIFixesView()
        case .health:
            HealthView()
        case .settings:
            SettingsView()
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

struct RootNavigationState {
    private(set) var section: SidebarItem = .fleet
    private var machinePath: [String] = []

    var tabSelection: SidebarItem {
        get {
            if case .machine = section { return .fleet }
            return section
        }
        set {
            section = newValue == .fleet
                ? machinePath.last.map(SidebarItem.machine) ?? .fleet
                : newValue
        }
    }

    var sidebarSelection: SidebarItem? {
        get { section }
        set {
            // A collapsing sidebar can clear its selection without navigating.
            guard let newValue else { return }
            section = newValue
            switch newValue {
            case .machine(let id): machinePath = [id]
            case .fleet: machinePath = []
            default: break
            }
        }
    }

    var dashboardPath: [String] {
        get { machinePath }
        set {
            machinePath = newValue
            if tabSelection == .fleet {
                section = newValue.last.map(SidebarItem.machine) ?? .fleet
            }
        }
    }
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
