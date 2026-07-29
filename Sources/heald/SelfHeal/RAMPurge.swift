import Foundation
import OSLog

/// Free RAM — adapted from meisterSiri `free` (user-safe; purge needs sudo ticket).
struct RAMPurge: Sendable {
    func purge(activityLog: ActivityLog) async {
        // Always drop purgeable memory hints via memory pressure simulation is invasive.
        // Prefer `purge` when passwordless sudo works; else notify only.
        let before = freeMB()
        let purge = SudoTicket.hasTicket()
            ? SudoTicket.runPrivileged("/usr/sbin/purge")
            : ShellRunner.run("/usr/bin/sudo", arguments: ["-n", "/usr/sbin/purge"])
        if purge.succeeded {
            await FleetAck.record(action: "ram_purge", result: "ok")
            let after = freeMB()
            let delta = after - before
            let summary = "RAM purge: free \(before)→\(after) MB (Δ\(delta))"
            try? await activityLog.log(event: ActivityEvent(
                type: .selfHealed,
                summary: summary
            ))
            Logger.healer.info("\(summary)")
            return
        }

        // Soft: restart Dock/Finder is too aggressive for enterprise auto — skip
        try? await activityLog.log(event: ActivityEvent(
            type: .healingAttempt,
            summary: "RAM pressure high — purge needs sudo ticket (skipped)",
            detail: "Run: heald free  (or configure passwordless purge)"
        ))
        Logger.healer.info("purge unavailable without sudo -n")
    }

    private func freeMB() -> Int {
        // vm_stat Pages free * page size
        let r = ShellRunner.run("/usr/bin/vm_stat", arguments: [])
        guard r.succeeded else { return 0 }
        var freePages = 0
        for line in r.output.split(separator: "\n") {
            if line.contains("Pages free") {
                let digits = line.filter(\.isNumber)
                freePages = Int(digits) ?? 0
            }
        }
        // page size 16384 on Apple Silicon typically
        return freePages * 16 / 1024 // pages * 16KB / 1024 = MB approx
    }
}
