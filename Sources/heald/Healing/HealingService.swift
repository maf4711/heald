import Foundation
import ServiceLifecycle
import OSLog

/// Orchestrates all healing actions. Runs on a 10s evaluation cycle.
struct HealingService: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    func run() async throws {
        var processHealer = ProcessHealer()

        while true {
            try await Task.sleep(for: .seconds(10))

            let processes = await store.processes
            guard processes.timestamp != .distantPast else { continue }

            let actions = await processHealer.evaluate(processes: processes, activityLog: activityLog)

            for action in actions {
                Logger.healer.info("Heal action: killed \(action.processName) via \(action.method)")
            }
        }
    }
}
