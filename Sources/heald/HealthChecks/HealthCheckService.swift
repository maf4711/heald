import Foundation
import ServiceLifecycle
import OSLog

/// Orchestrates all health checks on their own schedules.
/// - Crash detection: every 30s
/// - Disk I/O anomaly: every 30s
/// - DNS + Focus: every 60s
/// - LaunchAgent scan: every 300s
/// - Spotlight + iCloud ghosts: every 300s
/// - Hourly: Updates, Time Machine, Security suite, SSD Wear, Git repos
/// - Every 6h: Homebrew audit, Persistence audit, TCC audit
struct HealthCheckService: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    func run() async throws {
        let crashDetector = CrashDetector()
        let systemErrorScanner = SystemErrorScanner()
        let dnsChecker = DNSChecker()
        let launchAgentScanner = LaunchAgentScanner()
        let updateChecker = UpdateChecker()
        let focusChecker = FocusChecker()
        var diskIOAnomalyDetector = DiskIOAnomalyDetector()
        let timeMachineChecker = TimeMachineChecker()
        let fileVaultChecker = FileVaultChecker()
        let firewallChecker = FirewallChecker()
        let gatekeeperChecker = GatekeeperChecker()
        let sipChecker = SIPChecker()
        let xprotectChecker = XProtectChecker()
        let ssdWearChecker = SSDWearChecker()
        let homebrewAuditor = HomebrewAuditor()
        let persistenceAuditor = PersistenceAuditor()
        let tccAuditor = TCCAuditor()
        let spotlightHealer = SpotlightHealer()
        let icloudGhostCleaner = ICloudGhostCleaner()
        let gitRepoScanner = GitRepoScanner()

        var cycle = 0

        while true {
            try await Task.sleep(for: .seconds(30))
            cycle += 1

            // Crash detection (running processes) — every 30s
            let restarted = await crashDetector.check(activityLog: activityLog)
            if !restarted.isEmpty {
                Logger.health.info("Restarted: \(restarted.joined(separator: ", "))")
            }

            // Disk I/O anomaly detection — every 30s
            await diskIOAnomalyDetector.check(store: store, activityLog: activityLog)

            // DiagnosticReports + unified-log faults — every 60s
            if cycle % 2 == 0 {
                await systemErrorScanner.scan(activityLog: activityLog)
            }

            // DNS + Focus check — every 60s (cycle % 2 == 0)
            if cycle % 2 == 0 {
                await dnsChecker.check(activityLog: activityLog)
                _ = await focusChecker.check(store: store)
            }

            // LaunchAgent scan + Spotlight + iCloud — every 300s (cycle % 10 == 0)
            if cycle % 10 == 0 {
                await launchAgentScanner.scan(activityLog: activityLog)
                await spotlightHealer.check(activityLog: activityLog)
                await icloudGhostCleaner.check(activityLog: activityLog)
            }

            // Hourly checks — every 3600s (cycle % 120 == 0)
            if cycle % 120 == 0 {
                let report = updateChecker.check()
                if !report.outdatedBrewPackages.isEmpty || report.macOSUpdateAvailable {
                    Logger.health.info("Updates: brew=\(report.outdatedBrewPackages.count) macOS=\(report.macOSUpdateAvailable)")
                }

                // Time Machine
                await timeMachineChecker.check(store: store, activityLog: activityLog)

                // Full security suite
                let fileVaultEnabled = await fileVaultChecker.check(activityLog: activityLog)
                let firewallStatus = await firewallChecker.check(activityLog: activityLog)
                let gatekeeperEnabled = await gatekeeperChecker.check(activityLog: activityLog)
                let sipEnabled = await sipChecker.check(activityLog: activityLog)
                let xprotectStatus = await xprotectChecker.check(activityLog: activityLog)

                await store.updateSecurity(SecuritySnapshot(
                    fileVaultEnabled: fileVaultEnabled,
                    firewallEnabled: firewallStatus.enabled,
                    firewallStealthMode: firewallStatus.stealthMode,
                    gatekeeperEnabled: gatekeeperEnabled,
                    sipEnabled: sipEnabled,
                    xprotectVersion: xprotectStatus.version,
                    xprotectSignatureAgeDays: xprotectStatus.signatureAgeDays,
                    xprotectRemediatorVersion: xprotectStatus.remediatorVersion,
                    timestamp: Date()
                ))

                // SSD Wear
                await ssdWearChecker.check(store: store, activityLog: activityLog)

                // Git repos
                _ = await gitRepoScanner.scan(activityLog: activityLog)
            }

            // 6-hour checks — every 21600s (cycle % 720 == 0)
            if cycle % 720 == 0 {
                await homebrewAuditor.audit(activityLog: activityLog)
                _ = await persistenceAuditor.audit(activityLog: activityLog)
                _ = await tccAuditor.audit(activityLog: activityLog)
            }
        }
    }
}
