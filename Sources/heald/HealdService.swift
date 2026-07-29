import Foundation
import ServiceLifecycle
import OSLog

struct HealdService: Service {
    let store: MetricsStore

    func run() async throws {
        Logger.lifecycle.info("HealdService running — enterprise self-heal (no Meister dependency)")

        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        let dbPath = dataDir.appendingPathComponent("metrics.db").path
        let logPath = dataDir.appendingPathComponent("activity.ndjson").path

        let db = try MetricsDatabase(path: dbPath)
        let activityLog = try ActivityLog(path: logPath)
        let storageService = StorageService(store: store, db: db, activityLog: activityLog)
        let cloudPusher = CloudPusher(store: store, activityLog: activityLog)

        let ai = AppleIntelligenceClient()
        await ai.checkAvailability()

        let healingService = HealingService(store: store, activityLog: activityLog, ai: ai)
        let healthCheckService = HealthCheckService(store: store, activityLog: activityLog)
        let notificationService = NotificationService(store: store, activityLog: activityLog, ai: ai)
        let maintenanceService = MaintenanceService(store: store, db: db, activityLog: activityLog, ai: ai)
        let selfHeal = SelfHealOrchestrator(store: store, activityLog: activityLog)

        let cpuCollector = CPUCollector(store: store)
        let ramCollector = RAMCollector(store: store)
        let diskCollector = DiskCollector(store: store)
        let processCollector = ProcessCollector(store: store)
        let networkCollector = NetworkCollector(store: store)
        let batteryCollector = BatteryCollector(store: store)
        let uptimeCollector = UptimeCollector(store: store)
        let thermalCollector = ThermalCollector(store: store, activityLog: activityLog)
        let icloudCollector = ICloudCollector(store: store, activityLog: activityLog)
        let gpuCollector = GPUCollector(store: store)
        let bluetoothCollector = BluetoothCollector(store: store, activityLog: activityLog)
        let wifiCollector = WiFiCollector(store: store)
        let memoryLeakDetector = MemoryLeakDetector(store: store, activityLog: activityLog)
        let loginItemsCollector = LoginItemsCollector(store: store)
        let debugWriter = DebugStatusWriter(store: store)

        let collectorGroup = ServiceGroup(
            services: [
                cpuCollector, ramCollector, diskCollector, processCollector,
                networkCollector, batteryCollector, uptimeCollector, thermalCollector,
                icloudCollector, gpuCollector, bluetoothCollector, wifiCollector,
                memoryLeakDetector, loginItemsCollector,
                debugWriter, storageService, cloudPusher,
                healingService, healthCheckService, notificationService,
                maintenanceService, selfHeal,
            ],
            logger: .init(label: "com.heald.services")
        )

        try await collectorGroup.run()
    }
}
