import Foundation
import OSLog

/// Network self-heal: DNS flush + captive portal hint + high latency log.
struct NetworkSelfHeal {
    func evaluate(store: MetricsStore, activityLog: ActivityLog, policy: PolicyPack) async {
        guard policy.networkSelfHeal else { return }
        let net = await store.network
        guard net.timestamp != .distantPast else { return }

        // High latency to gateway
        if let lat = net.latencyMs, lat > 200 {
            Logger.health.warning("Network latency \(lat)ms on \(net.interfaceName)")
            try? await activityLog.log(event: ActivityEvent(
                type: .wifiPoorSignal,
                summary: "High gateway latency \(Int(lat))ms (\(net.interfaceName))"
            ))
        }

        // Packet loss
        if let loss = net.packetLossPercent, loss > 5 {
            Logger.health.warning("Packet loss \(loss)% — flushing DNS")
            if policy.allowsRemediation() {
                flushDNS()
                try? await activityLog.log(event: ActivityEvent(
                    type: .dnsFlushed,
                    summary: "DNS flush after \(loss)% packet loss"
                ))
                await FleetAck.record(action: "dns_flush", result: "ok", detail: "loss=\(loss)%")
            }
        }

        // Captive portal check (airport / connectivity)
        if await captiveLikely() {
            try? await activityLog.log(event: ActivityEvent(
                type: .wifiPoorSignal,
                summary: "Possible captive portal — open browser login page"
            ))
            NotificationService.sendNotification(
                title: "heald network",
                message: "Network may need browser login (captive portal)"
            )
        }
    }

    private func flushDNS() {
        if SudoTicket.hasTicket() {
            _ = SudoTicket.runPrivileged("/usr/bin/dscacheutil", arguments: ["-flushcache"])
            _ = SudoTicket.runPrivileged("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
        } else {
            _ = ShellRunner.run("/usr/bin/dscacheutil", arguments: ["-flushcache"])
        }
    }

    private func captiveLikely() async -> Bool {
        // Apple captive detection endpoint
        guard let url = URL(string: "http://captive.apple.com/hotspot-detect.html") else {
            return false
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            // Real success is "Success"; captive often returns HTML login
            if code == 200 && body.contains("Success") { return false }
            if body.lowercased().contains("html") && !body.contains("Success") { return true }
        } catch {
            return false
        }
        return false
    }
}
