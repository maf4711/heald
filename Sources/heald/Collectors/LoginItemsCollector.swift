import Foundation
import ServiceLifecycle
import OSLog

/// Audits login items (apps that start at login).
/// Scans LaunchAgents + SMAppService registered items.
/// Runs once at startup and then every 6 hours.
struct LoginItemsCollector: Service {
    let store: MetricsStore

    func run() async throws {
        Logger.collector.info("LoginItemsCollector started")

        while true {
            let snapshot = scanLoginItems()
            await store.updateLoginItems(snapshot)
            Logger.collector.info("LoginItems: \(snapshot.items.count) items found")

            try await Task.sleep(for: .seconds(21600)) // 6 hours
        }
    }

    private func scanLoginItems() -> LoginItemsSnapshot {
        var items: [LoginItemEntry] = []

        // 1. User LaunchAgents
        let launchAgentDir = "\(NSHomeDirectory())/Library/LaunchAgents"
        if let files = try? FileManager.default.contentsOfDirectory(atPath: launchAgentDir) {
            for file in files where file.hasSuffix(".plist") {
                let path = "\(launchAgentDir)/\(file)"
                let name = file.replacingOccurrences(of: ".plist", with: "")

                var isHidden = false
                if let data = FileManager.default.contents(atPath: path),
                   let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    // Check if it runs at load (effectively a login item)
                    let runsAtLoad = plist["RunAtLoad"] as? Bool ?? false
                    let keepAlive = plist["KeepAlive"] as? Bool ?? false
                    isHidden = !(runsAtLoad || keepAlive)
                }

                items.append(LoginItemEntry(name: name, path: path, isHidden: isHidden))
            }
        }

        // 2. Login Items from sfltool (macOS 13+)
        let result = ShellRunner.run("/usr/bin/sfltool", arguments: ["dumpbtm"])
        if result.succeeded {
            for line in result.output.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // Look for app entries
                if trimmed.contains("app:") || trimmed.contains("Name:") {
                    let name = trimmed.split(separator: ":").last?
                        .trimmingCharacters(in: .whitespaces) ?? trimmed
                    if !name.isEmpty && !items.contains(where: { $0.name.contains(name) }) {
                        items.append(LoginItemEntry(name: String(name), path: nil, isHidden: false))
                    }
                }
            }
        }

        return LoginItemsSnapshot(items: items, timestamp: Date())
    }
}
