import Foundation
import ServiceLifecycle
import OSLog

/// Monitors thermal state to detect CPU throttling.
/// Uses ProcessInfo.thermalState (no sudo required).
/// Polls every 30 seconds.
struct ThermalCollector: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    func run() async throws {
        Logger.collector.info("ThermalCollector started")

        var prevState: ProcessInfo.ThermalState = .nominal

        while true {
            let state = ProcessInfo.processInfo.thermalState

            let level: ThermalLevel = switch state {
            case .nominal: .nominal
            case .fair: .fair
            case .serious: .serious
            case .critical: .critical
            @unknown default: .nominal
            }

            let snapshot = ThermalSnapshot(thermalState: level, timestamp: Date())
            await store.updateThermal(snapshot)

            // Log state changes
            if state != prevState && state.rawValue > ProcessInfo.ThermalState.nominal.rawValue {
                try? await activityLog.log(event: ActivityEvent(
                    type: .thermalThrottling,
                    summary: "Thermal state changed to \(level.rawValue)",
                    detail: "Previous: \(thermalName(prevState)), Current: \(level.rawValue). System may throttle performance."
                ))
                Logger.collector.warning("Thermal state: \(level.rawValue)")
            }

            prevState = state
            try await Task.sleep(for: .seconds(30))
        }
    }

    private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
