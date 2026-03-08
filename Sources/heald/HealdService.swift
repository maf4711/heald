import Foundation
import ServiceLifecycle
import OSLog

struct HealdService: Service {
    let store: MetricsStore

    func run() async throws {
        Logger.lifecycle.info("HealdService running — starting metric collectors and storage")

        // --- Storage Layer (Phase 3) ---
        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        let dbPath = dataDir.appendingPathComponent("metrics.db").path
        let logPath = dataDir.appendingPathComponent("activity.ndjson").path

        let db = try MetricsDatabase(path: dbPath)
        let activityLog = try ActivityLog(path: logPath)
        let storageService = StorageService(store: store, db: db, activityLog: activityLog)
        let cloudPusher    = CloudPusher(store: store, activityLog: activityLog)

        // --- Healing (Phase 5) ---
        let healingService = HealingService(store: store, activityLog: activityLog)

        // --- Health Checks (Phase 6) ---
        let healthCheckService = HealthCheckService(store: store, activityLog: activityLog)

        // --- AI + Notifications (Phase 7) ---
        let ollamaClient = OllamaClient()
        await ollamaClient.checkAvailability()
        let notificationService = NotificationService(store: store, activityLog: activityLog, ollamaClient: ollamaClient)

        // --- Maintenance + Benchmark ---
        let maintenanceService = MaintenanceService(store: store, db: db, activityLog: activityLog, ollamaClient: ollamaClient)

        // --- Collectors ---
        let cpuCollector      = CPUCollector(store: store)
        let ramCollector      = RAMCollector(store: store)
        let diskCollector     = DiskCollector(store: store)
        let processCollector  = ProcessCollector(store: store)
        let networkCollector  = NetworkCollector(store: store)
        let batteryCollector  = BatteryCollector(store: store)
        let uptimeCollector   = UptimeCollector(store: store)
        let thermalCollector  = ThermalCollector(store: store, activityLog: activityLog)
        let debugWriter       = DebugStatusWriter(store: store)

        let collectorGroup = ServiceGroup(
            services: [cpuCollector, ramCollector, diskCollector, processCollector,
                       networkCollector, batteryCollector, uptimeCollector, thermalCollector,
                       debugWriter, storageService, cloudPusher, healingService,
                       healthCheckService, notificationService, maintenanceService],
            logger: .init(label: "com.heald.services")
        )

        try await collectorGroup.run()
    }
}
