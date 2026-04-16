import Foundation
import ServiceLifecycle
import OSLog

/// Monitors Wi-Fi signal strength, channel, and connection quality.
/// Uses the airport command-line utility built into macOS.
struct WiFiCollector: Service {
    let store: MetricsStore

    private let airportPath = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport"

    func run() async throws {
        Logger.collector.info("WiFiCollector started")

        while true {
            let snapshot = readWiFiInfo()
            await store.updateWiFi(snapshot)

            if let ssid = snapshot.ssid {
                Logger.collector.debug(
                    "WiFi: \(ssid) RSSI=\(snapshot.rssi)dBm SNR=\(snapshot.snr)dB ch\(snapshot.channel) \(snapshot.channelBand) \(snapshot.txRate)Mbps [\(snapshot.signalQuality)]"
                )
            }

            try await Task.sleep(for: .seconds(30))
        }
    }

    private func readWiFiInfo() -> WiFiSnapshot {
        // Try airport -I for current connection info
        let result = ShellRunner.run(airportPath, arguments: ["-I"])
        guard result.succeeded else {
            // Fall back to networksetup
            return readViaNetworkSetup()
        }

        let output = result.output
        guard !output.contains("AirPort: Off") else { return .empty }

        var ssid: String?
        var bssid: String?
        var rssi = 0
        var noise = 0
        var channel = 0
        var txRate = 0.0
        var securityType = ""

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "SSID": ssid = value
            case "BSSID": bssid = value
            case "agrCtlRSSI": rssi = Int(value) ?? 0
            case "agrCtlNoise": noise = Int(value) ?? 0
            case "channel": channel = Int(value.split(separator: ",").first ?? "") ?? 0
            case "lastTxRate": txRate = Double(value) ?? 0
            case "link auth": securityType = value
            default: break
            }
        }

        let snr = rssi - noise
        let band = channelToBand(channel)

        return WiFiSnapshot(
            ssid: ssid, bssid: bssid,
            rssi: rssi, noise: noise, snr: snr,
            channel: channel, channelBand: band,
            txRate: txRate, securityType: securityType,
            timestamp: Date()
        )
    }

    private func readViaNetworkSetup() -> WiFiSnapshot {
        let result = ShellRunner.run("/usr/sbin/networksetup", arguments: ["-getairportnetwork", "en0"])
        guard result.succeeded else { return .empty }

        let output = result.output
        guard output.contains("Current Wi-Fi Network:") else { return .empty }

        let ssid = output.split(separator: ":").last?.trimmingCharacters(in: .whitespacesAndNewlines)

        return WiFiSnapshot(
            ssid: ssid, bssid: nil,
            rssi: 0, noise: 0, snr: 0,
            channel: 0, channelBand: "",
            txRate: 0, securityType: "",
            timestamp: Date()
        )
    }

    private func channelToBand(_ channel: Int) -> String {
        switch channel {
        case 1...14: return "2.4 GHz"
        case 32...177: return "5 GHz"
        case 1...233 where channel > 177: return "6 GHz"
        default: return "Unknown"
        }
    }
}
