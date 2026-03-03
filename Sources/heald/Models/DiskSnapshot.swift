import Foundation

struct VolumeSpaceInfo: Sendable {
    let mountPoint: String
    let volumeName: String
    let totalBytes: Int64
    let freeBytes: Int64
}

struct DiskIODelta: Sendable {
    let readBytes: Int64
    let writeBytes: Int64
    let interval: TimeInterval
}

/// Cumulative counters — used internally for delta calculation
struct DiskIOCounters: Sendable {
    let readBytes: Int64
    let writeBytes: Int64
}

struct SMARTInfo: Sendable {
    let bsdName: String
    let status: String           // "Verified" / "Failing" / "Not Supported"
    let availableSpare: Int?
    let percentageUsed: Int?
    let temperature: Int?
    let powerOnHours: Int?
}

struct DiskSnapshot: Sendable {
    let volumes: [VolumeSpaceInfo]
    let io: [DiskIODelta]
    let smart: [SMARTInfo]
    let timestamp: Date

    static let empty = DiskSnapshot(volumes: [], io: [], smart: [], timestamp: .distantPast)
}
