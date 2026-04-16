import Foundation

struct BluetoothDevice: Sendable {
    let name: String
    let address: String
    let batteryPercent: Int?    // nil if not supported
    let isConnected: Bool
    let deviceType: String      // "Keyboard", "Mouse", "Headphones", etc.
}

struct BluetoothSnapshot: Sendable {
    let devices: [BluetoothDevice]
    let timestamp: Date

    static let empty = BluetoothSnapshot(devices: [], timestamp: .distantPast)
}
