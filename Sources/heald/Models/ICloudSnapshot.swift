import Foundation

struct ICloudSnapshot: Sendable {
    let isEnabled: Bool
    let optimizeStorage: Bool
    let localFiles: Int
    let cloudFiles: Int
    let totalFiles: Int
    let syncPercent: Double         // 0.0–100.0
    let directories: Int
    let evictedDirs: [String]
    let conflicts: Int
    let docsSize: Int64             // bytes
    let diskFree: Int64             // bytes
    let birdRunning: Bool
    let timestamp: Date

    static let empty = ICloudSnapshot(
        isEnabled: false, optimizeStorage: false,
        localFiles: 0, cloudFiles: 0, totalFiles: 0, syncPercent: 0,
        directories: 0, evictedDirs: [], conflicts: 0,
        docsSize: 0, diskFree: 0, birdRunning: false,
        timestamp: .distantPast
    )
}
