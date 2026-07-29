import Foundation
import ServiceLifecycle
import OSLog

/// Orchestrates maintenance by **delegating batch work to Meister**
/// (`meisterSiri` / `meister`) and keeping heald-native continuous tasks
/// (benchmark, optional native cleaners as fallback).
///
/// Schedule (local time):
/// - 02:00 daily — system benchmark (native)
/// - 09:15 daily — Meister `--quick` (lean modules + autofix)
/// - Sunday 10:30 — Meister `--deep` (full suite)
///
/// Legacy native brew/cache cleaners still run at 03:00 / Sun 04:00 as a
/// light fallback when Meister is missing; when Meister is installed they
/// are skipped to avoid double work.
struct MaintenanceService: Service {
    let store: MetricsStore
    let db: MetricsDatabase
    let activityLog: ActivityLog
    let ai: AppleIntelligenceClient

    func run() async throws {
        Logger.maintenance.info(
            "MaintenanceService started (Meister integration: \(MeisterClient.isInstalled ? "on" : "fallback-native"))"
        )

        let homebrewMaintainer = HomebrewMaintainer()
        let systemCleaner = SystemCleaner()
        let clamAVScanner = ClamAVScanner()
        let systemBenchmark = SystemBenchmark()
        let deepClean = DeepClean()
        let selfHealingRunner = SelfHealingRunner(
            ai: ai,
            activityLog: activityLog
        )

        // One-time: Spotlight fix for MAS apps
        await systemCleaner.fixSpotlightForMASApps(activityLog: activityLog)

        // Track which hour slots we already fired today (avoid re-run every hour tick)
        var lastDailyQuickDay: Int?
        var lastDeepWeek: Int?
        var lastBenchmarkDay: Int?
        var lastNativeDailyDay: Int?
        var lastNativeWeeklyWeek: Int?

        while true {
            try await Task.sleep(for: .seconds(300)) // 5 min tick — finer schedule match

            let now = Date()
            let cal = Calendar.current
            let parts = cal.dateComponents([.hour, .minute, .weekday, .day, .weekOfYear, .year], from: now)
            let hour = parts.hour ?? 0
            let minute = parts.minute ?? 0
            let day = parts.day ?? 0
            let week = (parts.year ?? 0) * 100 + (parts.weekOfYear ?? 0)
            let weekday = parts.weekday ?? 0 // 1 = Sunday

            // ── Daily benchmark at 02:00 ──
            if hour == 2 && minute < 10 && lastBenchmarkDay != day {
                lastBenchmarkDay = day
                Logger.benchmark.info("Starting daily benchmark...")
                await selfHealingRunner.runSafe(name: "Benchmark") {
                    let result = try await systemBenchmark.runAll(activityLog: activityLog)
                    await store.updateBenchmark(result)
                    try await db.insertBenchmark(result)
                }
            }

            // ── Meister daily --quick ~09:15 (matches meister LaunchAgent) ──
            if hour == 9 && minute >= 10 && minute < 25 && lastDailyQuickDay != day {
                lastDailyQuickDay = day
                await runMeisterProfile(.quick, label: "daily-quick")
            }

            // ── Meister weekly --deep Sunday ~10:30 ──
            if weekday == 1 && hour == 10 && minute >= 25 && minute < 40 && lastDeepWeek != week {
                lastDeepWeek = week
                await runMeisterProfile(.deep, label: "weekly-deep")
            }

            // ── Native fallback only when Meister missing ──
            if !MeisterClient.isInstalled {
                if hour == 3 && minute < 10 && lastNativeDailyDay != day {
                    lastNativeDailyDay = day
                    await runNativeDaily(
                        homebrewMaintainer: homebrewMaintainer,
                        systemCleaner: systemCleaner,
                        selfHealingRunner: selfHealingRunner
                    )
                }
                if weekday == 1 && hour == 4 && minute < 10 && lastNativeWeeklyWeek != week {
                    lastNativeWeeklyWeek = week
                    await runNativeWeekly(
                        homebrewMaintainer: homebrewMaintainer,
                        systemCleaner: systemCleaner,
                        clamAVScanner: clamAVScanner,
                        deepClean: deepClean,
                        selfHealingRunner: selfHealingRunner
                    )
                }
            }
        }
    }

    // MARK: - Meister profiles

    private func runMeisterProfile(_ profile: MeisterClient.Profile, label: String) async {
        Logger.maintenance.info("Starting Meister \(profile.rawValue) (\(label))...")
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceStarted,
            summary: "Meister \(profile.rawValue) started (\(label))"
        ))

        let result = await Task.detached {
            MeisterClient.maintain(profile: profile, dryRun: false, quiet: true)
        }.value

        let summary: String
        if result.exitCode == 127 {
            summary = "Meister missing — skipped \(label)"
            Logger.maintenance.warning("\(summary)")
        } else {
            summary = "Meister \(profile.rawValue) exit \(result.exitCode) in \(result.durationMs)ms (\(label))"
            Logger.maintenance.info("\(summary)")
        }

        try? await activityLog.log(event: ActivityEvent(
            type: result.succeeded ? .maintenanceCompleted : .maintenanceStarted,
            summary: summary,
            detail: String(result.stderr.suffix(400))
        ))

        // Refresh bridge view after maintain
        let snap = MeisterClient.readLastJSON()
        let pref = MeisterBridgeService.preferredMaintainCLI(
            preferredTwinPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".meister/preferred_twin")
        )
        MeisterBridgeService.writeHealdView(snap: snap, preferred: pref)
    }

    // MARK: - Native fallback (no Meister)

    private func runNativeDaily(
        homebrewMaintainer: HomebrewMaintainer,
        systemCleaner: SystemCleaner,
        selfHealingRunner: SelfHealingRunner
    ) async {
        Logger.maintenance.info("Native daily maintenance (Meister not installed)...")
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceStarted,
            summary: "Native daily maintenance started"
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
        await selfHealingRunner.runSafe(name: "LargeFiles") {
            try await systemCleaner.findLargeFiles(activityLog: activityLog)
        }
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceCompleted,
            summary: "Native daily maintenance completed"
        ))
    }

    private func runNativeWeekly(
        homebrewMaintainer: HomebrewMaintainer,
        systemCleaner: SystemCleaner,
        clamAVScanner: ClamAVScanner,
        deepClean: DeepClean,
        selfHealingRunner: SelfHealingRunner
    ) async {
        Logger.maintenance.info("Native weekly maintenance (Meister not installed)...")
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceStarted,
            summary: "Native weekly maintenance started"
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
        await selfHealingRunner.runSafe(name: "DeepClean") {
            await deepClean.run(activityLog: activityLog)
        }
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceCompleted,
            summary: "Native weekly maintenance completed"
        ))
    }
}
