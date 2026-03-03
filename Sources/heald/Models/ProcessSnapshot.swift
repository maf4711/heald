import Foundation

struct ProcessEntry: Sendable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let ramBytes: Int64
    let uid: Int
    let isSystem: Bool
}

struct ProcessSnapshot: Sendable {
    let byCPU: [ProcessEntry]    // top 25 by CPU
    let byRAM: [ProcessEntry]    // top 25 by RAM
    let timestamp: Date

    static let empty = ProcessSnapshot(byCPU: [], byRAM: [], timestamp: .distantPast)
}
