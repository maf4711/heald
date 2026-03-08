import Foundation

/// Results from a daily system benchmark run.
struct BenchmarkSnapshot: Sendable {
    let cpuSingleCore: Double    // ops/sec (prime computations)
    let cpuMultiCore: Double     // ops/sec (parallel prime computations)
    let diskWriteMBs: Double     // MB/s sequential write
    let diskReadMBs: Double      // MB/s sequential read
    let memoryBandwidthGBs: Double // GB/s memory copy throughput
    let durationSeconds: Double  // total benchmark time
    let coreCount: Int           // number of CPU cores used
    let timestamp: Date

    static let empty = BenchmarkSnapshot(
        cpuSingleCore: 0, cpuMultiCore: 0,
        diskWriteMBs: 0, diskReadMBs: 0,
        memoryBandwidthGBs: 0, durationSeconds: 0,
        coreCount: 0, timestamp: .distantPast
    )

    /// Compute a normalized score (0-100) for quick health comparison.
    /// Based on typical Apple Silicon Mac ranges.
    var overallScore: Int {
        // Weighted: CPU single 25%, CPU multi 25%, disk 25%, memory 25%
        let cpuSingleScore = min(cpuSingleCore / 50_000, 1.0)     // 50k ops/s = 100%
        let cpuMultiScore = min(cpuMultiCore / 400_000, 1.0)       // 400k ops/s = 100%
        let diskScore = min((diskWriteMBs + diskReadMBs) / 10_000, 1.0)  // 10 GB/s combined = 100%
        let memScore = min(memoryBandwidthGBs / 50, 1.0)           // 50 GB/s = 100%

        return Int((cpuSingleScore * 25 + cpuMultiScore * 25 + diskScore * 25 + memScore * 25).rounded())
    }
}

/// Network quality snapshot for periodic checks.
struct NetworkSnapshot: Sendable {
    let interfaceName: String     // en0, en1, etc.
    let rxBytesPerSec: Double     // download throughput
    let txBytesPerSec: Double     // upload throughput
    let latencyMs: Double?        // ping to gateway
    let packetLossPercent: Double? // packet loss to gateway
    let timestamp: Date

    static let empty = NetworkSnapshot(
        interfaceName: "en0",
        rxBytesPerSec: 0, txBytesPerSec: 0,
        latencyMs: nil, packetLossPercent: nil,
        timestamp: .distantPast
    )
}

/// Battery health snapshot (MacBooks only).
struct BatterySnapshot: Sendable {
    let isPresent: Bool
    let cycleCount: Int
    let maxCapacityPercent: Int   // design capacity remaining
    let currentCharge: Int        // current charge percentage
    let isCharging: Bool
    let condition: String         // "Normal", "Service Recommended", etc.
    let temperature: Double?      // celsius
    let timestamp: Date

    static let empty = BatterySnapshot(
        isPresent: false, cycleCount: 0, maxCapacityPercent: 100,
        currentCharge: 0, isCharging: false, condition: "Unknown",
        temperature: nil, timestamp: .distantPast
    )
}

/// System uptime information.
struct UptimeSnapshot: Sendable {
    let systemUptimeSeconds: Double
    let daemonUptimeSeconds: Double
    let lastReboot: Date
    let timestamp: Date

    static let empty = UptimeSnapshot(
        systemUptimeSeconds: 0, daemonUptimeSeconds: 0,
        lastReboot: .distantPast, timestamp: .distantPast
    )

    var systemUptimeFormatted: String {
        let days = Int(systemUptimeSeconds / 86400)
        let hours = Int(systemUptimeSeconds.truncatingRemainder(dividingBy: 86400) / 3600)
        if days > 0 { return "\(days)d \(hours)h" }
        let mins = Int(systemUptimeSeconds.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hours)h \(mins)m"
    }
}

/// Thermal state from the system.
struct ThermalSnapshot: Sendable {
    let thermalState: ThermalLevel
    let timestamp: Date

    static let empty = ThermalSnapshot(thermalState: .nominal, timestamp: .distantPast)
}

enum ThermalLevel: String, Codable, Sendable {
    case nominal    // Normal operation
    case fair       // Slightly elevated, minor throttling possible
    case serious    // Significant throttling
    case critical   // Maximum throttling, system at risk
}
