import Foundation
import ServiceLifecycle
import OSLog

/// Scheduled enterprise maintenance — **100% native** (no Meister CLI).
/// Profiles adapted from meisterSiri quick/deep semantics.
///
/// - 02:00 daily — system benchmark
/// - 09:15 daily — quick: brew update/upgrade light path, orphan agents, proactive heal
/// - Sunday 10:30 — deep: caches, trash, derived data, deep clean, full brew
struct MaintenanceService: Service {
    let store: MetricsStore
    let db: MetricsDatabase
    let activityLog: ActivityLog
    let ai: AppleIntelligenceClient

    func run() async throws {
        Logger.maintenance.info("MaintenanceService started (enterprise native)")

        let homebrewMaintainer = HomebrewMaintainer()
        let systemCleaner = SystemCleaner()
        let clamAVScanner = ClamAVScanner()
        let systemBenchmark = SystemBenchmark()
        let deepClean = DeepClean()
        let proactive = ProactiveHealer()
        let autofix = AutofixEngine()
        let selfHealingRunner = SelfHealingRunner(
            ai: ai,
            activityLog: activityLog
        )

        await systemCleaner.fixSpotlightForMASApps(activityLog: activityLog)

        var lastQuickDay: Int?
        var lastDeepWeek: Int?
        var lastBenchmarkDay: Int?

        while true {
            try await Task.sleep(for: .seconds(300))

            let now = Date()
            let cal = Calendar.current
            let parts = cal.dateComponents([.hour, .minute, .weekday, .day, .weekOfYear, .year], from: now)
            let hour = parts.hour ?? 0
            let minute = parts.minute ?? 0
            let day = parts.day ?? 0
            let week = (parts.year ?? 0) * 100 + (parts.weekOfYear ?? 0)
            let weekday = parts.weekday ?? 0

            if hour == 2 && minute < 10 && lastBenchmarkDay != day {
                lastBenchmarkDay = day
                Logger.benchmark.info("Starting daily benchmark...")
                await selfHealingRunner.runSafe(name: "Benchmark") {
                    let result = try await systemBenchmark.runAll(activityLog: activityLog)
                    await store.updateBenchmark(result)
                    try await db.insertBenchmark(result)
                }
            }

            // Daily ~09:15: prefer MeisterSiri once/day; native quick if no CLI
            if hour == 9 && minute >= 10 && minute < 25 && lastQuickDay != day {
                lastQuickDay = day
                let policy = PolicyPack.load()
                if policy.meisterBridgeEnabled ?? true {
                    let outcome = MeisterBridgeRunner.tick()
                    switch outcome.action {
                    case "ran", "skipped_already_today", "skipped_lock":
                        break
                    default:
                        await runQuick(
                            homebrew: homebrewMaintainer,
                            proactive: proactive,
                            autofix: autofix,
                            selfHealingRunner: selfHealingRunner
                        )
                    }
                } else {
                    await runQuick(
                        homebrew: homebrewMaintainer,
                        proactive: proactive,
                        autofix: autofix,
                        selfHealingRunner: selfHealingRunner
                    )
                }
            }

            // Weekly deep Sunday ~10:30
            if weekday == 1 && hour == 10 && minute >= 25 && minute < 40 && lastDeepWeek != week {
                lastDeepWeek = week
                await runDeep(
                    homebrew: homebrewMaintainer,
                    systemCleaner: systemCleaner,
                    clamAV: clamAVScanner,
                    deepClean: deepClean,
                    proactive: proactive,
                    autofix: autofix,
                    selfHealingRunner: selfHealingRunner
                )
            }

            // Safe softwareupdate inside maintenance window (policy opt-in)
            if minute < 5 {
                let policy = await PolicyStore.shared.current()
                await SafeSoftwareUpdate().maybeRun(activityLog: activityLog, policy: policy)
            }
        }
    }

    // MARK: - Profiles (callable from CLI)

    func runQuick(
        homebrew: HomebrewMaintainer,
        proactive: ProactiveHealer,
        autofix: AutofixEngine,
        selfHealingRunner: SelfHealingRunner
    ) async {
        Logger.maintenance.info("Quick maintain starting...")
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceStarted,
            summary: "Quick maintain (enterprise)"
        ))
        await proactive.run(activityLog: activityLog)
        await autofix.quarantineOrphanAgents(activityLog: activityLog)
        await selfHealingRunner.runSafe(name: "Homebrew") {
            try await homebrew.updateAndUpgrade(activityLog: activityLog)
        }
        await selfHealingRunner.runSafe(name: "MAS") {
            try await homebrew.updateMAS(activityLog: activityLog)
        }
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceCompleted,
            summary: "Quick maintain completed"
        ))
        Logger.maintenance.info("Quick maintain done")
    }

    func runDeep(
        homebrew: HomebrewMaintainer,
        systemCleaner: SystemCleaner,
        clamAV: ClamAVScanner,
        deepClean: DeepClean,
        proactive: ProactiveHealer,
        autofix: AutofixEngine,
        selfHealingRunner: SelfHealingRunner
    ) async {
        Logger.maintenance.info("Deep maintain starting...")
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceStarted,
            summary: "Deep maintain (enterprise)"
        ))
        await runQuick(
            homebrew: homebrew,
            proactive: proactive,
            autofix: autofix,
            selfHealingRunner: selfHealingRunner
        )
        await selfHealingRunner.runSafe(name: "Caches") {
            try await systemCleaner.cleanCaches(activityLog: activityLog)
        }
        await selfHealingRunner.runSafe(name: "Trash") {
            try await systemCleaner.emptyTrash(activityLog: activityLog)
        }
        await selfHealingRunner.runSafe(name: "DerivedData") {
            try await systemCleaner.cleanXcodeDerivedData(activityLog: activityLog)
        }
        await selfHealingRunner.runSafe(name: "DeepClean") {
            await deepClean.run(activityLog: activityLog)
        }
        await selfHealingRunner.runSafe(name: "ClamAV") {
            try await clamAV.scan(activityLog: activityLog)
        }
        await selfHealingRunner.runSafe(name: "Periodic") {
            try await systemCleaner.runPeriodicMaintenance(activityLog: activityLog)
        }
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceCompleted,
            summary: "Deep maintain completed"
        ))
        Logger.maintenance.info("Deep maintain done")
    }
}

/// Static entry points for CLI (same profiles as daemon schedule).
enum MaintainProfiles {
    static func quick(activityLog: ActivityLog, ai: AppleIntelligenceClient) async {
        let svc = MaintenanceService(
            store: MetricsStore(),
            db: try! MetricsDatabase(path: NSTemporaryDirectory() + "heald-cli.db"),
            activityLog: activityLog,
            ai: ai
        )
        let runner = SelfHealingRunner(ai: ai, activityLog: activityLog)
        await svc.runQuick(
            homebrew: HomebrewMaintainer(),
            proactive: ProactiveHealer(),
            autofix: AutofixEngine(),
            selfHealingRunner: runner
        )
    }

    static func deep(activityLog: ActivityLog, ai: AppleIntelligenceClient) async {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/cli-maintain.db").path
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let db = try! MetricsDatabase(path: path)
        let svc = MaintenanceService(
            store: MetricsStore(),
            db: db,
            activityLog: activityLog,
            ai: ai
        )
        let runner = SelfHealingRunner(ai: ai, activityLog: activityLog)
        await svc.runDeep(
            homebrew: HomebrewMaintainer(),
            systemCleaner: SystemCleaner(),
            clamAV: ClamAVScanner(),
            deepClean: DeepClean(),
            proactive: ProactiveHealer(),
            autofix: AutofixEngine(),
            selfHealingRunner: runner
        )
    }
}
