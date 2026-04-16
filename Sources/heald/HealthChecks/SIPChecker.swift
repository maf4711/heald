import Foundation
import OSLog

/// Checks if System Integrity Protection (SIP) is enabled.
struct SIPChecker {
    func check(activityLog: ActivityLog) async -> Bool {
        let result = ShellRunner.run("/usr/bin/csrutil", arguments: ["status"])
        let enabled = result.output.contains("enabled")

        if !enabled {
            Logger.health.warning("SIP (System Integrity Protection) is DISABLED — security risk!")
            try? await activityLog.log(event: ActivityEvent(
                type: .sipDisabled,
                summary: "System Integrity Protection is disabled",
                detail: "SIP can only be re-enabled from Recovery Mode"
            ))
        } else {
            Logger.health.info("SIP: enabled")
        }

        return enabled
    }
}
