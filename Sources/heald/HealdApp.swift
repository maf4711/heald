import ArgumentParser
import ServiceLifecycle
import OSLog

struct HealdApp: AsyncParsableCommand {
    static let version = "1.0.0"  // Full implementation — Phases 3-7

    static let configuration = CommandConfiguration(
        commandName: "heald",
        abstract: "Self-healing macOS system daemon",
        version: version
    )

    func run() async throws {
        Logger.lifecycle.info("heald \(Self.version) starting")

        let store = MetricsStore()
        let service = HealdService(store: store)
        let serviceGroup = ServiceGroup(
            services: [service],
            gracefulShutdownSignals: [.sigterm, .sigint],
            logger: .init(label: "com.heald.daemon")
        )

        try await serviceGroup.run()
        Logger.lifecycle.info("heald stopped cleanly")
    }
}
