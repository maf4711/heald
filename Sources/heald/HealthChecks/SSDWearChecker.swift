import Foundation
import OSLog

/// Monitors SSD wear via APFS container info and NVMe SMART attributes.
/// Warns when percentage used exceeds threshold or available spare drops.
struct SSDWearChecker {
    /// Warn when NVMe percentage used exceeds this
    private let wearThresholdPercent = 80
    /// Warn when available spare drops below this
    private let spareThresholdPercent = 20

    func check(store: MetricsStore, activityLog: ActivityLog) async {
        let snapshot = readSSDWear()
        await store.updateSSDWear(snapshot)

        // Check thresholds
        if let pctUsed = snapshot.percentageUsed, pctUsed >= wearThresholdPercent {
            Logger.health.warning("SSD wear high: \(pctUsed)% used")
            try? await activityLog.log(event: ActivityEvent(
                type: .ssdWearWarning,
                summary: "SSD wear at \(pctUsed)% (threshold: \(wearThresholdPercent)%)",
                detail: snapshot.availableSpare.map { "Available spare: \($0)%" }
            ))
        }

        if let spare = snapshot.availableSpare, spare <= spareThresholdPercent {
            Logger.health.warning("SSD spare low: \(spare)%")
            try? await activityLog.log(event: ActivityEvent(
                type: .ssdWearWarning,
                summary: "SSD available spare at \(spare)% (threshold: \(spareThresholdPercent)%)"
            ))
        }

        if let life = snapshot.estimatedLifeRemainingPercent {
            Logger.health.info("SSD: \(life)% life remaining")
        }
    }

    private func readSSDWear() -> SSDWearSnapshot {
        // Read NVMe SMART data via diskutil for disk0 (boot drive)
        let result = ShellRunner.run("/usr/sbin/diskutil", arguments: ["info", "-plist", "disk0"])
        guard result.succeeded, let data = result.output.data(using: .utf8) else {
            return .empty
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any] else {
            return .empty
        }

        let smartKeys = plist["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any]

        let percentageUsed = smartKeys?["PERCENTAGE_USED"] as? Int
        let availableSpare = smartKeys?["AVAILABLE_SPARE"] as? Int
        let powerOnHours = smartKeys?["POWER_ON_HOURS_0"] as? Int

        // Data units written (in 512KB units * 1000)
        var dataWrittenTB: Double?
        if let unitsLow = smartKeys?["DATA_UNITS_WRITTEN_0"] as? Int64 {
            // Each unit = 1000 * 512 bytes = 500KB
            dataWrittenTB = Double(unitsLow) * 500_000 / 1_099_511_627_776
        }

        // Estimated life remaining based on percentage used
        var lifeRemaining: Int?
        if let pctUsed = percentageUsed {
            lifeRemaining = max(0, 100 - pctUsed)
        }

        // APFS container info is supplementary; primary metrics come from NVMe SMART

        return SSDWearSnapshot(
            percentageUsed: percentageUsed,
            availableSpare: availableSpare,
            dataWrittenTB: dataWrittenTB,
            powerOnHours: powerOnHours,
            estimatedLifeRemainingPercent: lifeRemaining,
            timestamp: Date()
        )
    }
}
