import Foundation

struct Machine: Identifiable, Codable, Hashable {
    var id: String { machineId }
    let machineId: String
    let hostname: String
    let lastSeen: Date
    let cpu: CPUMetrics
    let ram: RAMMetrics
    let disk: DiskMetrics
    let processes: ProcessMetrics
    let network: NetworkMetrics?
    let battery: BatteryMetrics?
    let uptime: UptimeMetrics?
    let thermal: String?
    let benchmark: BenchmarkMetrics?
    let icloud: ICloudMetrics?

    var status: StatusLevel {
        let age = Date().timeIntervalSince(lastSeen)
        if age > 120 { return .offline }
        if ram.pressureLevel >= 4 || cpu.overallUnit > 0.95 { return .critical }
        if ram.pressureLevel >= 2 || cpu.overallUnit > 0.80 { return .warning }
        return .healthy
    }

    var lastSeenFormatted: String {
        let age = Date().timeIntervalSince(lastSeen)
        if age < 30 { return "just now" }
        if age < 60 { return "\(Int(age))s ago" }
        if age < 3600 { return "\(Int(age / 60))m ago" }
        if age < 86400 { return "\(Int(age / 3600))h ago" }
        return "\(Int(age / 86400))d ago"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(machineId)
    }

    static func == (lhs: Machine, rhs: Machine) -> Bool {
        lhs.machineId == rhs.machineId
    }
}

struct CPUMetrics: Codable, Hashable {
    let overall: Double
    let perCore: [Double]

    /// 0–100 for UI
    var overallPercent: Int {
        // API may send fraction (0–1) or already percent
        let v = overall > 1.5 ? overall : overall * 100
        return Int(v.rounded())
    }

    /// 0–1 for progress bars
    var overallUnit: Double {
        overall > 1.5 ? min(overall / 100, 1) : min(overall, 1)
    }

    /// Per-core as 0–1
    func coreUnit(_ value: Double) -> Double {
        value > 1.5 ? min(value / 100, 1) : min(value, 1)
    }
}

struct RAMMetrics: Codable, Hashable {
    let usedGB: Double
    let wiredGB: Double
    let compressedGB: Double
    let swapUsedMB: Double
    let pressureLevel: Int

    var pressureText: String {
        switch pressureLevel {
        case 1: return "Normal"
        case 2: return "Warning"
        case 4: return "Critical"
        default: return "Unknown"
        }
    }
}

struct DiskMetrics: Codable, Hashable {
    let volumes: [VolumeInfo]
    let smart: [SMARTStatus]
}

struct VolumeInfo: Identifiable, Codable, Hashable {
    var id: String { mountPoint }
    let name: String
    let mountPoint: String
    let totalGB: Double
    let freeGB: Double

    var usedGB: Double { totalGB - freeGB }
    var usedPercent: Double { totalGB > 0 ? usedGB / totalGB : 0 }
}

struct SMARTStatus: Identifiable, Codable, Hashable {
    var id: String { bsdName }
    let bsdName: String
    let status: String

    var isHealthy: Bool { status == "Verified" || status.lowercased() == "verified" }
}

struct ProcessMetrics: Codable, Hashable {
    let topCPU: [HealdProcess]
    let topRAM: [HealdProcess]
}

/// Process row from heald API (not Foundation.ProcessInfo).
struct HealdProcess: Identifiable, Codable, Hashable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let ramMB: Double
    let system: Bool
}

// MARK: - Extended Metrics

struct NetworkMetrics: Codable, Hashable {
    let interface: String
    let rxBytesPerSec: Double
    let txBytesPerSec: Double
    let latencyMs: Double?
    let packetLossPercent: Double?
}

struct BatteryMetrics: Codable, Hashable {
    let cycleCount: Int
    let maxCapacityPercent: Int
    let currentCharge: Int
    let isCharging: Bool
    let condition: String
    let temperature: Double?
}

struct UptimeMetrics: Codable, Hashable {
    let systemSeconds: Int
    let daemonSeconds: Int
    let systemFormatted: String
}

struct BenchmarkMetrics: Codable, Identifiable, Hashable {
    var id: String { timestamp }
    let cpuSingleCore: Double
    let cpuMultiCore: Double
    let diskWriteMBs: Double
    let diskReadMBs: Double
    let memoryBandwidthGBs: Double
    let overallScore: Int
    let coreCount: Int
    let timestamp: String
}

struct ICloudMetrics: Codable, Hashable {
    let isEnabled: Bool
    let optimizeStorage: Bool
    let localFiles: Int
    let cloudFiles: Int
    let syncPercent: Double
    let directories: Int
    let evictedDirs: [String]
    let conflicts: Int
    let docsSizeGB: Double
    let diskFreeGB: Double
    let birdRunning: Bool
}

// MARK: - History

struct MachineWithHistory: Identifiable, Codable {
    var id: String { machineId }
    let machineId: String
    let hostname: String
    let lastSeen: Date
    let cpu: CPUMetrics
    let ram: RAMMetrics
    let disk: DiskMetrics
    let processes: ProcessMetrics
    let network: NetworkMetrics?
    let battery: BatteryMetrics?
    let uptime: UptimeMetrics?
    let thermal: String?
    let benchmark: BenchmarkMetrics?
    let icloud: ICloudMetrics?
    let history: [MetricSnapshot]?
    let benchmarkHistory: [BenchmarkMetrics]?

    var asMachine: Machine {
        Machine(
            machineId: machineId, hostname: hostname, lastSeen: lastSeen,
            cpu: cpu, ram: ram, disk: disk, processes: processes,
            network: network, battery: battery, uptime: uptime,
            thermal: thermal, benchmark: benchmark, icloud: icloud
        )
    }
}

struct MetricSnapshot: Codable, Identifiable, Hashable {
    var id: String { timestamp }
    let timestamp: String
    let cpuOverall: Double
    let ramUsedGB: Double

    enum CodingKeys: String, CodingKey {
        case timestamp
        case cpuOverall = "cpu"
        case ramUsedGB
    }

    /// 0–1 for charts
    var cpuUnit: Double {
        cpuOverall > 1.5 ? min(cpuOverall / 100, 1) : min(cpuOverall, 1)
    }
}
