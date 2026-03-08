import Foundation
import ServiceLifecycle
import OSLog

/// Monitors battery health for MacBooks.
/// Polls every 5 minutes — battery state changes slowly.
struct BatteryCollector: Service {
    let store: MetricsStore

    func run() async throws {
        Logger.collector.info("BatteryCollector started")

        while true {
            let snapshot = readBatteryInfo()
            await store.updateBattery(snapshot)

            try await Task.sleep(for: .seconds(300)) // 5 minutes
        }
    }

    private func readBatteryInfo() -> BatterySnapshot {
        // Use ioreg to get battery info (works without sudo)
        let result = ShellRunner.run("/usr/sbin/ioreg", arguments: [
            "-rc", "AppleSmartBattery", "-w0"
        ])

        guard result.succeeded else {
            return BatterySnapshot(
                isPresent: false, cycleCount: 0, maxCapacityPercent: 100,
                currentCharge: 0, isCharging: false, condition: "N/A",
                temperature: nil, timestamp: Date()
            )
        }

        let output = result.output

        // Check if battery exists
        guard output.contains("AppleSmartBattery") else {
            return BatterySnapshot(
                isPresent: false, cycleCount: 0, maxCapacityPercent: 100,
                currentCharge: 0, isCharging: false, condition: "N/A",
                temperature: nil, timestamp: Date()
            )
        }

        let cycleCount = extractInt(from: output, key: "CycleCount") ?? 0
        let maxCapacity = extractInt(from: output, key: "MaxCapacity") ?? 100
        let currentCapacity = extractInt(from: output, key: "CurrentCapacity") ?? 0
        let designCapacity = extractInt(from: output, key: "DesignCapacity") ?? maxCapacity
        let isCharging = output.contains("\"IsCharging\" = Yes")
        let temperature = extractInt(from: output, key: "Temperature")

        // Health = MaxCapacity / DesignCapacity * 100
        let healthPercent = designCapacity > 0 ? (maxCapacity * 100) / designCapacity : 100

        // Charge percentage
        let chargePercent = maxCapacity > 0 ? (currentCapacity * 100) / maxCapacity : 0

        // Condition from system_profiler (cached, expensive call)
        let condition = readBatteryCondition()

        // Temperature is in centi-degrees
        let tempCelsius = temperature.map { Double($0) / 100.0 }

        return BatterySnapshot(
            isPresent: true,
            cycleCount: cycleCount,
            maxCapacityPercent: healthPercent,
            currentCharge: chargePercent,
            isCharging: isCharging,
            condition: condition,
            temperature: tempCelsius,
            timestamp: Date()
        )
    }

    private func extractInt(from text: String, key: String) -> Int? {
        // Pattern: "Key" = 1234
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("\"\(key)\"") {
                let parts = trimmed.split(separator: "=")
                if parts.count >= 2 {
                    let val = parts[1].trimmingCharacters(in: .whitespaces)
                    return Int(val)
                }
            }
        }
        return nil
    }

    private func readBatteryCondition() -> String {
        let result = ShellRunner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPPowerDataType", "-detailLevel", "mini"]
        )
        guard result.succeeded else { return "Unknown" }

        for line in result.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Condition:") {
                return trimmed.replacingOccurrences(of: "Condition:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return "Normal"
    }
}
