import SwiftUI

@main
struct HealdWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .tint(Color(red: 0, green: 229 / 255, blue: 160 / 255))
        }
    }
}
