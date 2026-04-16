import Foundation

/// GPU utilization snapshot via IOKit (Apple Silicon unified memory).
struct GPUSnapshot: Sendable {
    let utilizationPercent: Double   // 0.0–1.0 fraction
    let inUseSystemMemoryBytes: Int64
    let allocatedSystemMemoryBytes: Int64
    let deviceName: String
    let timestamp: Date

    static let empty = GPUSnapshot(
        utilizationPercent: 0, inUseSystemMemoryBytes: 0,
        allocatedSystemMemoryBytes: 0, deviceName: "Unknown",
        timestamp: .distantPast
    )
}
