import Foundation
import OSLog

/// Checks if FileVault disk encryption is enabled.
struct FileVaultChecker {
    func check(activityLog: ActivityLog) async -> Bool {
        let result = ShellRunner.run("/usr/bin/fdesetup", arguments: ["status"])
        guard result.succeeded else {
            Logger.health.warning("FileVault: fdesetup failed")
            return false
        }

        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let enabled = output.contains("FileVault is On")

        if !enabled {
            Logger.health.warning("FileVault is DISABLED — disk is not encrypted")
            try? await activityLog.log(event: ActivityEvent(
                type: .fileVaultDisabled,
                summary: "FileVault disk encryption is disabled",
                detail: output
            ))
        } else {
            Logger.health.info("FileVault: enabled")
        }

        return enabled
    }
}
