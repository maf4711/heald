import ServiceLifecycle
import OSLog

struct HealdService: Service {
    let store: MetricsStore

    func run() async throws {
        Logger.lifecycle.info("HealdService running — starting metric collectors")

        let cpuCollector     = CPUCollector(store: store)
        let ramCollector     = RAMCollector(store: store)
        let diskCollector    = DiskCollector(store: store)
        let processCollector = ProcessCollector(store: store)
        let debugWriter      = DebugStatusWriter(store: store)

        let collectorGroup = ServiceGroup(
            services: [cpuCollector, ramCollector, diskCollector, processCollector, debugWriter],
            logger: .init(label: "com.heald.collectors")
        )

        try await collectorGroup.run()
    }
}
