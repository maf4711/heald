import Foundation
import ServiceLifecycle
import OSLog

/// HLTH-03: Orchestrates health checks on their own schedules.
/// - Crash detection: every 30s
/// - DNS check: every 60s
/// - LaunchAgent scan: every 300s
/// - Update check: every 3600s (1h)
struct HealthCheckService: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    func run() async throws {
        let crashDetector = CrashDetector()
        let dnsChecker = DNSChecker()
        let launchAgentScanner = LaunchAgentScanner()
        let updateChecker = UpdateChecker()

        var cycle = 0

        while true {
            try await Task.sleep(for: .seconds(30))
            cycle += 1

            // Crash detection — every 30s
            let restarted = await crashDetector.check(activityLog: activityLog)
            if !restarted.isEmpty {
                Logger.health.info("Restarted: \(restarted.joined(separator: ", "))")
            }

            // DNS check — every 60s (cycle % 2 == 0)
            if cycle % 2 == 0 {
                await dnsChecker.check(activityLog: activityLog)
            }

            // LaunchAgent scan — every 300s (cycle % 10 == 0)
            if cycle % 10 == 0 {
                await launchAgentScanner.scan(activityLog: activityLog)
            }

            // Update check — every 3600s (cycle % 120 == 0)
            if cycle % 120 == 0 {
                let report = updateChecker.check()
                if !report.outdatedBrewPackages.isEmpty || report.macOSUpdateAvailable {
                    Logger.health.info("Updates: brew=\(report.outdatedBrewPackages.count) macOS=\(report.macOSUpdateAvailable)")
                }
            }
        }
    }
}
