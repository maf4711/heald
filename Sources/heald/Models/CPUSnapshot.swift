import Foundation

struct CPUSnapshot: Sendable {
    let overall: Double          // 0.0–1.0 fraction
    let perCore: [Double]        // 0.0–1.0 per core
    let timestamp: Date

    static let zero = CPUSnapshot(overall: 0, perCore: [], timestamp: .distantPast)
}
