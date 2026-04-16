import Foundation
import OSLog

/// Checks if Gatekeeper is enabled (blocks unsigned apps).
struct GatekeeperChecker {
    func check(activityLog: ActivityLog) async -> Bool {
        let result = ShellRunner.run("/usr/sbin/spctl", arguments: ["--status"])
        let enabled = result.output.contains("enabled")

        if !enabled {
            Logger.health.warning("Gatekeeper is DISABLED")
            try? await activityLog.log(event: ActivityEvent(
                type: .gatekeeperDisabled,
                summary: "Gatekeeper is disabled — unsigned apps can run freely",
                detail: result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        } else {
            Logger.health.info("Gatekeeper: enabled")
        }

        return enabled
    }
}
