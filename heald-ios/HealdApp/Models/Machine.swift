import Foundation

struct Machine: Identifiable, Codable {
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

    var status: StatusLevel {
        let age = Date().timeIntervalSince(lastSeen)
        if age > 120 { return .offline }
        if ram.pressureLevel >= 4 || cpu.overall > 0.95 { return .critical }
        if ram.pressureLevel >= 2 || cpu.overall > 0.80 { return .warning }
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
}

struct CPUMetrics: Codable {
    let overall: Double
    let perCore: [Double]

    var overallPercent: Int { Int(overall * 100) }
}

struct RAMMetrics: Codable {
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

struct DiskMetrics: Codable {
    let volumes: [VolumeInfo]
    let smart: [SMARTStatus]
}

struct VolumeInfo: Identifiable, Codable {
    var id: String { mountPoint }
    let name: String
    let mountPoint: String
    let totalGB: Double
    let freeGB: Double

    var usedGB: Double { totalGB - freeGB }
    var usedPercent: Double { totalGB > 0 ? usedGB / totalGB : 0 }
}

struct SMARTStatus: Identifiable, Codable {
    var id: String { bsdName }
    let bsdName: String
    let status: String

    var isHealthy: Bool { status == "Verified" }
}

struct ProcessMetrics: Codable {
    let topCPU: [ProcessInfo]
    let topRAM: [ProcessInfo]
}

struct ProcessInfo: Identifiable, Codable {
    var id: Int32 { pid }
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let ramMB: Double
    let system: Bool
}

// MARK: - Extended Metrics

struct NetworkMetrics: Codable {
    let interface: String
    let rxBytesPerSec: Double
    let txBytesPerSec: Double
    let latencyMs: Double?
    let packetLossPercent: Double?
}

struct BatteryMetrics: Codable {
    let cycleCount: Int
    let maxCapacityPercent: Int
    let currentCharge: Int
    let isCharging: Bool
    let condition: String
    let temperature: Double?
}

struct UptimeMetrics: Codable {
    let systemSeconds: Int
    let daemonSeconds: Int
    let systemFormatted: String
}

struct BenchmarkMetrics: Codable, Identifiable {
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
    let history: [MetricSnapshot]?
    let benchmarkHistory: [BenchmarkMetrics]?

    var asMachine: Machine {
        Machine(
            machineId: machineId, hostname: hostname, lastSeen: lastSeen,
            cpu: cpu, ram: ram, disk: disk, processes: processes,
            network: network, battery: battery, uptime: uptime,
            thermal: thermal, benchmark: benchmark
        )
    }
}

struct MetricSnapshot: Codable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let cpuOverall: Double
    let ramUsedGB: Double

    enum CodingKeys: String, CodingKey {
        case timestamp
        case cpuOverall = "cpu"
        case ramUsedGB
    }
}
