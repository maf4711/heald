import Foundation
import ServiceLifecycle
import OSLog

/// Tracks system uptime and daemon uptime.
/// Updates every 60 seconds.
struct UptimeCollector: Service {
    let store: MetricsStore
    private let daemonStartTime = Date()

    func run() async throws {
        Logger.collector.info("UptimeCollector started")

        while true {
            let systemUptime = ProcessInfo.processInfo.systemUptime
            let daemonUptime = Date().timeIntervalSince(daemonStartTime)
            let lastReboot = Date(timeIntervalSinceNow: -systemUptime)

            let snapshot = UptimeSnapshot(
                systemUptimeSeconds: systemUptime,
                daemonUptimeSeconds: daemonUptime,
                lastReboot: lastReboot,
                timestamp: Date()
            )

            await store.updateUptime(snapshot)

            try await Task.sleep(for: .seconds(60))
        }
    }
}
