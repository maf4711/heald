import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0

    var body: some View {
        if !appState.isConfigured {
            SettingsView(isOnboarding: true)
        } else {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "square.grid.2x2")
                    }
                    .tag(0)
                JournalView()
                    .tabItem {
                        Label("Journal", systemImage: "list.bullet.rectangle")
                    }
                    .tag(1)
                AIFixesView()
                    .tabItem {
                        Label("AI Fixes", systemImage: "brain")
                    }
                    .tag(2)
                HealthView()
                    .tabItem {
                        Label("Health", systemImage: "heart.text.clipboard")
                    }
                    .tag(3)
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(4)
            }
            .tint(Theme.accent)
            .overlay {
                if appState.isLoading && appState.machines.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("Lade Daten...")
                            .foregroundStyle(.secondary)
                        if let error = appState.error {
                            Text(error)
                                .foregroundStyle(.red)
                                .padding(.top, 8)
                            Button("Erneut versuchen") {
                                Task { await appState.refresh() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                }
            }
            .task {
                await appState.refresh()
                appState.startAutoRefresh()
            }
        }
    }
}
