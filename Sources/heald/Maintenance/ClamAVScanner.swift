import Foundation
import OSLog

/// ClamAV virus scanning with automatic definition updates.
struct ClamAVScanner {

    func scan(activityLog: ActivityLog) async throws {
        guard let clamscan = ShellRunner.findExecutable("clamscan") else {
            Logger.maintenance.info("ClamAV not installed — skipping virus scan")
            return
        }

        let brew = ShellRunner.findExecutable("brew")

        // Ensure freshclam.conf exists
        if let brew {
            let prefixResult = ShellRunner.run(brew, arguments: ["--prefix"])
            if prefixResult.succeeded {
                let prefix = prefixResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                let configDir = "\(prefix)/etc/clamav"
                let configPath = "\(configDir)/freshclam.conf"
                let samplePath = "\(configDir)/freshclam.conf.sample"

                if !FileManager.default.fileExists(atPath: configPath),
                   FileManager.default.fileExists(atPath: samplePath) {
                    try? FileManager.default.copyItem(atPath: samplePath, toPath: configPath)
                    // Comment out Example line
                    if var content = try? String(contentsOfFile: configPath, encoding: .utf8) {
                        content = content.replacingOccurrences(of: "\nExample", with: "\n#Example")
                        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
                    }
                    Logger.maintenance.info("Created freshclam.conf from sample")
                }
            }
        }

        // Update virus definitions
        if let freshclam = ShellRunner.findExecutable("freshclam") {
            Logger.maintenance.info("Updating ClamAV virus definitions...")
            let updateResult = ShellRunner.run(freshclam)

            if updateResult.succeeded {
                Logger.maintenance.info("Virus definitions updated")
            } else {
                Logger.maintenance.warning("freshclam had issues: \(updateResult.errorOutput.prefix(200))")
            }
        }

        // Run scan
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        Logger.maintenance.info("Running ClamAV scan on \(home)...")

        let result = ShellRunner.run(
            clamscan,
            arguments: ["-r", "--bell", "-i", "--exclude-dir=^/Volumes", home]
        )

        let summary: String
        let detail: String?

        switch result.exitCode {
        case 0:
            summary = "ClamAV: no malware found"
            detail = nil
        case 1:
            summary = "ClamAV: MALWARE FOUND"
            detail = result.output
            NotificationService.sendNotification(
                title: "heald: Malware gefunden!",
                message: "ClamAV hat Malware erkannt. Pruefe das Activity Log."
            )
        default:
            summary = "ClamAV: scan error (exit \(result.exitCode))"
            detail = result.errorOutput
        }

        try await activityLog.log(event: ActivityEvent(
            type: .clamavScan,
            summary: summary,
            detail: detail.map { String($0.prefix(2000)) }
        ))

        Logger.maintenance.info("\(summary)")

        if result.exitCode == 1 {
            throw MaintenanceError.failed(summary)
        }
    }
}
