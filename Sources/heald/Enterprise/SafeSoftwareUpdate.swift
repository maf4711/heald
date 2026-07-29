import Foundation
import OSLog

/// Safe softwareupdate: security-labeled patches only, inside maintenance window.
struct SafeSoftwareUpdate {
    func maybeRun(activityLog: ActivityLog, policy: PolicyPack) async {
        guard policy.safeSoftwareUpdate else { return }
        guard policy.allowsRemediation() else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        let start = policy.maintenanceWindowStartHour
        let end = policy.maintenanceWindowEndHour
        let inWindow: Bool
        if start <= end {
            inWindow = hour >= start && hour < end
        } else {
            // overnight window e.g. 22–5
            inWindow = hour >= start || hour < end
        }
        guard inWindow else {
            Logger.maintenance.debug("SafeSoftwareUpdate: outside maintenance window")
            return
        }

        guard SudoTicket.hasTicket() else {
            Logger.maintenance.info("SafeSoftwareUpdate: needs sudo ticket")
            return
        }

        // List recommended
        let list = SudoTicket.runPrivileged("/usr/sbin/softwareupdate", arguments: ["-l"])
        let text = list.output + list.errorOutput
        // Only act if security/recommended labels appear
        let lower = text.lowercased()
        guard lower.contains("security") || lower.contains("recommended") else {
            Logger.maintenance.info("SafeSoftwareUpdate: no security updates listed")
            return
        }

        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceStarted,
            summary: "Safe softwareupdate: installing recommended/security"
        ))

        // --recommended installs Apple's recommended set (includes security)
        let r = SudoTicket.runPrivileged(
            "/usr/sbin/softwareupdate",
            arguments: ["-i", "--recommended", "--agree-to-license"]
        )
        let summary = r.succeeded
            ? "Safe softwareupdate completed"
            : "Safe softwareupdate failed: \(r.errorOutput.prefix(200))"
        try? await activityLog.log(event: ActivityEvent(
            type: r.succeeded ? .maintenanceCompleted : .healingFailed,
            summary: summary
        ))
        await FleetAck.record(
            action: "softwareupdate",
            result: r.succeeded ? "ok" : "fail",
            detail: String(summary.prefix(300))
        )
        await WebhookNotifier.shared.emit(
            title: "Software Update",
            text: summary,
            severity: r.succeeded ? "info" : "warning"
        )
    }
}
