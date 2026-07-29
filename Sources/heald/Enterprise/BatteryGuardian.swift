import Foundation
import OSLog

/// Battery health degradation early warning.
struct BatteryGuardian {
    func evaluate(store: MetricsStore, activityLog: ActivityLog, policy: PolicyPack) async {
        guard policy.batteryGuardian else { return }
        let b = await store.battery
        guard b.isPresent, b.timestamp != .distantPast else { return }

        var warnings: [String] = []
        if b.maxCapacityPercent < policy.batteryHealthMinPct {
            warnings.append("health \(b.maxCapacityPercent)% < \(policy.batteryHealthMinPct)%")
        }
        if b.cycleCount >= policy.batteryCycleWarn {
            warnings.append("cycles \(b.cycleCount) ≥ \(policy.batteryCycleWarn)")
        }
        if b.condition.lowercased().contains("service") {
            warnings.append("condition=\(b.condition)")
        }

        guard !warnings.isEmpty else { return }

        let msg = warnings.joined(separator: "; ")
        Logger.health.warning("Battery guardian: \(msg)")
        try? await activityLog.log(event: ActivityEvent(
            type: .diskWarning, // reuse generic health — or battery-specific if we add
            summary: "Battery: \(msg)",
            detail: "charge=\(b.currentCharge)% temp=\(b.temperature.map { String($0) } ?? "n/a")"
        ))
        NotificationService.sendNotification(title: "heald battery", message: msg)
        await WebhookNotifier.shared.emit(title: "Battery", text: msg, severity: "warning")
        await FleetAck.record(action: "battery_warn", result: "alert", detail: msg)
    }
}
