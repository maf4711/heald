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
            .task {
                await appState.refresh()
                appState.startAutoRefresh()
            }
        }
    }
}
