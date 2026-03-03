import Foundation

struct RAMSnapshot: Sendable {
    let used: Double             // bytes
    let wired: Double            // bytes
    let active: Double           // bytes
    let compressed: Double       // bytes
    let swapUsed: Double         // bytes
    let swapTotal: Double        // bytes
    let pressureLevel: Int       // 1=normal, 2=warning, 4=critical
    let timestamp: Date

    static let zero = RAMSnapshot(
        used: 0, wired: 0, active: 0, compressed: 0,
        swapUsed: 0, swapTotal: 0, pressureLevel: 1,
        timestamp: .distantPast
    )
}
