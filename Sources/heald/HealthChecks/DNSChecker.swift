import Foundation
import OSLog

/// HEAL-05: Detects DNS problems and flushes cache.
struct DNSChecker {
    /// Domains to probe for DNS health.
    private let probes = ["google.com", "apple.com", "cloudflare.com"]

    func check(activityLog: ActivityLog) async {
        var failures = 0

        for domain in probes {
            if !canResolve(domain) {
                failures += 1
            }
        }

        // If majority of probes fail, DNS is likely broken
        guard failures >= 2 else { return }

        Logger.health.warning("DNS appears broken (\(failures)/\(self.probes.count) probes failed) — flushing")
        flushDNS()

        try? await activityLog.log(event: ActivityEvent(
            type: .dnsFlushed,
            summary: "DNS cache flushed (\(failures)/\(probes.count) probes failed)",
            beforeState: "DNS resolution failing",
            afterState: "DNS cache flushed via dscacheutil"
        ))
    }

    private func canResolve(_ domain: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/host")
        task.arguments = ["-W", "3", domain]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func flushDNS() {
        // dscacheutil doesn't need sudo
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/dscacheutil")
        task.arguments = ["-flushcache"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Logger.health.error("dscacheutil failed: \(error)")
        }
    }
}
