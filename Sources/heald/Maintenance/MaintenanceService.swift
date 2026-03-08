import Foundation
import ServiceLifecycle
import OSLog

/// Orchestrates all maintenance tasks (adapted from meister2026.sh).
/// Daily tasks run at 03:00, weekly tasks on Sundays at 04:00.
struct MaintenanceService: Service {
    let activityLog: ActivityLog
    let ollamaClient: OllamaClient

    func run() async throws {
        Logger.maintenance.info("MaintenanceService started")

        let homebrewMaintainer = HomebrewMaintainer()
        let systemCleaner = SystemCleaner()
        let clamAVScanner = ClamAVScanner()
        let ollamaModelUpdater = OllamaModelUpdater()
        let selfHealingRunner = SelfHealingRunner(
            ollamaClient: ollamaClient,
            activityLog: activityLog
        )

        // One-time: Spotlight fix for MAS apps
        await systemCleaner.fixSpotlightForMASApps(activityLog: activityLog)

        while true {
            try await Task.sleep(for: .seconds(3600)) // 1 hour tick

            let now = Calendar.current.dateComponents([.hour, .weekday], from: Date())

            // ── Daily maintenance at 03:00 ──
            if now.hour == 3 {
                Logger.maintenance.info("Starting daily maintenance...")

                try? await activityLog.log(event: ActivityEvent(
                    type: .maintenanceStarted,
                    summary: "Daily maintenance started"
                ))

                await selfHealingRunner.runSafe(name: "Homebrew") {
                    try await homebrewMaintainer.updateAndUpgrade(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "MAS") {
                    try await homebrewMaintainer.updateMAS(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "OfficeUpdate") {
                    try await homebrewMaintainer.updateOffice(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "OllamaModels") {
                    try await ollamaModelUpdater.updateAllModels(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "LargeFiles") {
                    try await systemCleaner.findLargeFiles(activityLog: activityLog)
                }

                try? await activityLog.log(event: ActivityEvent(
                    type: .maintenanceCompleted,
                    summary: "Daily maintenance completed"
                ))

                Logger.maintenance.info("Daily maintenance completed")
            }

            // ── Weekly maintenance on Sundays at 04:00 ──
            if now.hour == 4 && now.weekday == 1 {
                Logger.maintenance.info("Starting weekly maintenance...")

                try? await activityLog.log(event: ActivityEvent(
                    type: .maintenanceStarted,
                    summary: "Weekly maintenance started"
                ))

                await selfHealingRunner.runSafe(name: "AppMigration") {
                    try await homebrewMaintainer.migrateMASApps(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "CacheCleaner") {
                    try await systemCleaner.cleanCaches(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "TrashCleanup") {
                    try await systemCleaner.emptyTrash(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "XcodeDerivedData") {
                    try await systemCleaner.cleanXcodeDerivedData(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "ClamAV") {
                    try await clamAVScanner.scan(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "PeriodicMaintenance") {
                    try await systemCleaner.runPeriodicMaintenance(activityLog: activityLog)
                }

                await selfHealingRunner.runSafe(name: "LMStudioSync") {
                    try await ollamaModelUpdater.syncToLMStudio(activityLog: activityLog)
                }

                try? await activityLog.log(event: ActivityEvent(
                    type: .maintenanceCompleted,
                    summary: "Weekly maintenance completed"
                ))

                Logger.maintenance.info("Weekly maintenance completed")
            }
        }
    }
}
