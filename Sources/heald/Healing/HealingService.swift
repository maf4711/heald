import Foundation
import ServiceLifecycle
import OSLog

/// Orchestrates all healing actions. Runs on a 10s evaluation cycle.
/// Optional Apple Intelligence consult before kill; rules always as fallback.
struct HealingService: Service {
    let store: MetricsStore
    let activityLog: ActivityLog
    let ai: AppleIntelligenceClient

    func run() async throws {
        var processHealer = ProcessHealer()

        while true {
            try await Task.sleep(for: .seconds(10))

            let policy = await PolicyStore.shared.current()
            guard policy.selfHealEnabled, policy.processKillEnabled, policy.allowsRemediation() else {
                continue
            }

            let processes = await store.processes
            guard processes.timestamp != .distantPast else { continue }

            let actions = await processHealer.evaluate(
                processes: processes,
                activityLog: activityLog,
                ai: ai
            )

            for action in actions {
                Logger.healer.info("Heal action: killed \(action.processName) via \(action.method)")
                await FleetAck.record(
                    action: "process_kill",
                    result: "ok",
                    detail: "\(action.processName) via \(action.method)"
                )
            }
        }
    }
}
