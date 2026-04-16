import Foundation

struct WiFiSnapshot: Sendable {
    let ssid: String?
    let bssid: String?
    let rssi: Int               // signal strength in dBm (e.g. -55)
    let noise: Int              // noise floor in dBm (e.g. -90)
    let snr: Int                // signal-to-noise ratio
    let channel: Int
    let channelBand: String     // "2.4 GHz", "5 GHz", "6 GHz"
    let txRate: Double          // Mbps
    let securityType: String    // "WPA3", "WPA2", etc.
    let timestamp: Date

    static let empty = WiFiSnapshot(
        ssid: nil, bssid: nil, rssi: 0, noise: 0, snr: 0,
        channel: 0, channelBand: "", txRate: 0, securityType: "",
        timestamp: .distantPast
    )

    var signalQuality: String {
        switch rssi {
        case -50...0: return "excellent"
        case -60 ..< -50: return "good"
        case -70 ..< -60: return "fair"
        default: return "poor"
        }
    }
}
