import Foundation
import ServiceLifecycle
import OSLog

/// Monitors network throughput via netstat counters and gateway latency.
/// Polls every 30 seconds for throughput, pings gateway every 60 seconds.
struct NetworkCollector: Service {
    let store: MetricsStore

    func run() async throws {
        Logger.collector.info("NetworkCollector started")

        var previousRx: Int64 = 0
        var previousTx: Int64 = 0
        var cycle = 0

        while true {
            try await Task.sleep(for: .seconds(30))
            cycle += 1

            let (rx, tx, iface) = readNetworkCounters()

            var rxPerSec: Double = 0
            var txPerSec: Double = 0

            if previousRx > 0 {
                let deltaRx = rx - previousRx
                let deltaTx = tx - previousTx
                if deltaRx >= 0 && deltaTx >= 0 {
                    rxPerSec = Double(deltaRx) / 30.0
                    txPerSec = Double(deltaTx) / 30.0
                }
            }

            previousRx = rx
            previousTx = tx

            // Ping gateway every 60s (every other cycle)
            var latency: Double? = nil
            var packetLoss: Double? = nil
            if cycle % 2 == 0 {
                (latency, packetLoss) = pingGateway()
            }

            let snapshot = NetworkSnapshot(
                interfaceName: iface,
                rxBytesPerSec: rxPerSec,
                txBytesPerSec: txPerSec,
                latencyMs: latency,
                packetLossPercent: packetLoss,
                timestamp: Date()
            )

            await store.updateNetwork(snapshot)
        }
    }

    /// Read cumulative byte counters from netstat for the primary interface.
    private func readNetworkCounters() -> (rx: Int64, tx: Int64, iface: String) {
        let result = ShellRunner.run("/usr/bin/netstat", arguments: ["-ibn"])
        guard result.succeeded else { return (0, 0, "en0") }

        var bestIface = "en0"
        var bestRx: Int64 = 0
        var bestTx: Int64 = 0

        for line in result.output.split(separator: "\n") {
            let cols = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            // Format: Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
            guard cols.count >= 10 else { continue }
            let iface = cols[0]

            // Only look at en0/en1 (WiFi/Ethernet) with Link# entries
            guard (iface == "en0" || iface == "en1"),
                  cols[2].hasPrefix("Link") else { continue }

            if let ibytes = Int64(cols[6]), let obytes = Int64(cols[9]) {
                if ibytes > bestRx {
                    bestIface = iface
                    bestRx = ibytes
                    bestTx = obytes
                }
            }
        }

        return (bestRx, bestTx, bestIface)
    }

    /// Ping the default gateway to measure latency and packet loss.
    private func pingGateway() -> (latencyMs: Double?, packetLoss: Double?) {
        // Get default gateway
        let routeResult = ShellRunner.run("/usr/sbin/route", arguments: ["-n", "get", "default"])
        guard routeResult.succeeded else { return (nil, nil) }

        var gateway: String? = nil
        for line in routeResult.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                gateway = trimmed.replacingOccurrences(of: "gateway:", with: "").trimmingCharacters(in: .whitespaces)
                break
            }
        }

        guard let gw = gateway, !gw.isEmpty else { return (nil, nil) }

        // Ping with 3 packets, 2s timeout
        let pingResult = ShellRunner.run("/sbin/ping", arguments: ["-c", "3", "-W", "2000", gw])

        var latency: Double? = nil
        var loss: Double? = nil

        for line in pingResult.output.split(separator: "\n") {
            let s = String(line)
            // "round-trip min/avg/max/stddev = 1.234/2.345/3.456/0.567 ms"
            if s.contains("round-trip") || s.contains("rtt") {
                let parts = s.split(separator: "=")
                if parts.count >= 2 {
                    let values = parts[1].trimmingCharacters(in: .whitespaces).split(separator: "/")
                    if values.count >= 2 {
                        latency = Double(values[1]) // avg
                    }
                }
            }
            // "3 packets transmitted, 3 packets received, 0.0% packet loss"
            if s.contains("packet loss") {
                let comps = s.split(separator: ",")
                for comp in comps {
                    let trimmed = comp.trimmingCharacters(in: .whitespaces)
                    if trimmed.contains("% packet loss") {
                        let num = trimmed.split(separator: "%").first.flatMap { Double($0) }
                        loss = num
                    }
                }
            }
        }

        return (latency, loss)
    }
}
