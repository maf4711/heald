import SwiftUI

@main
struct HealdMacApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopover()
                .environment(appState)
        } label: {
            Image(systemName: appState.menuBarIcon)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.window)

        Window("Heald Dashboard", id: "dashboard") {
            MainWindow()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 720)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsPane()
                .environment(appState)
                .preferredColorScheme(.dark)
        }
    }
}
