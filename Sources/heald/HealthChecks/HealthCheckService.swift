import Foundation
import ServiceLifecycle
import OSLog

/// HLTH-03: Orchestrates health checks on their own schedules.
/// - Crash detection: every 30s
/// - DNS check: every 60s
/// - Focus check: every 60s
/// - Disk I/O anomaly: every 30s
/// - LaunchAgent scan: every 300s
/// - Time Machine: every 3600s
/// - Security (FileVault, Firewall): every 3600s
/// - SSD Wear: every 3600s
/// - Homebrew audit: every 21600s (6h)
/// - Update check: every 3600s (1h)
struct HealthCheckService: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    func run() async throws {
        let crashDetector = CrashDetector()
        let dnsChecker = DNSChecker()
        let launchAgentScanner = LaunchAgentScanner()
        let updateChecker = UpdateChecker()
        let focusChecker = FocusChecker()
        var diskIOAnomalyDetector = DiskIOAnomalyDetector()
        let timeMachineChecker = TimeMachineChecker()
        let fileVaultChecker = FileVaultChecker()
        let firewallChecker = FirewallChecker()
        let ssdWearChecker = SSDWearChecker()
        let homebrewAuditor = HomebrewAuditor()

        var cycle = 0

        while true {
            try await Task.sleep(for: .seconds(30))
            cycle += 1

            // Crash detection — every 30s
            let restarted = await crashDetector.check(activityLog: activityLog)
            if !restarted.isEmpty {
                Logger.health.info("Restarted: \(restarted.joined(separator: ", "))")
            }

            // Disk I/O anomaly detection — every 30s
            await diskIOAnomalyDetector.check(store: store, activityLog: activityLog)

            // DNS check — every 60s (cycle % 2 == 0)
            if cycle % 2 == 0 {
                await dnsChecker.check(activityLog: activityLog)
                _ = await focusChecker.check(store: store)
            }

            // LaunchAgent scan — every 300s (cycle % 10 == 0)
            if cycle % 10 == 0 {
                await launchAgentScanner.scan(activityLog: activityLog)
            }

            // Hourly checks — every 3600s (cycle % 120 == 0)
            if cycle % 120 == 0 {
                let report = updateChecker.check()
                if !report.outdatedBrewPackages.isEmpty || report.macOSUpdateAvailable {
                    Logger.health.info("Updates: brew=\(report.outdatedBrewPackages.count) macOS=\(report.macOSUpdateAvailable)")
                }

                // Time Machine
                await timeMachineChecker.check(store: store, activityLog: activityLog)

                // Security checks
                let fileVaultEnabled = await fileVaultChecker.check(activityLog: activityLog)
                let firewallStatus = await firewallChecker.check(activityLog: activityLog)
                await store.updateSecurity(SecuritySnapshot(
                    fileVaultEnabled: fileVaultEnabled,
                    firewallEnabled: firewallStatus.enabled,
                    firewallStealthMode: firewallStatus.stealthMode,
                    timestamp: Date()
                ))

                // SSD Wear
                await ssdWearChecker.check(store: store, activityLog: activityLog)
            }

            // Homebrew security audit — every 6h (cycle % 720 == 0)
            if cycle % 720 == 0 {
                await homebrewAuditor.audit(activityLog: activityLog)
            }
        }
    }
}
