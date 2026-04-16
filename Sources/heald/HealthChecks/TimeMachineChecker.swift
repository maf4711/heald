import Foundation
import OSLog

/// Checks Time Machine backup status and warns if backups are stale.
struct TimeMachineChecker {
    /// Warn if last backup is older than 48 hours
    private let staleThresholdHours: Double = 48

    func check(store: MetricsStore, activityLog: ActivityLog) async {
        let snapshot = readTimeMachineStatus()
        await store.updateTimeMachine(snapshot)

        if !snapshot.isConfigured {
            Logger.health.info("Time Machine: not configured")
            try? await activityLog.log(event: ActivityEvent(
                type: .timeMachineNotConfigured,
                summary: "Time Machine is not configured"
            ))
            return
        }

        if let hours = snapshot.hoursSinceLastBackup, hours > staleThresholdHours {
            Logger.health.warning("Time Machine: last backup \(Int(hours))h ago (threshold: \(Int(self.staleThresholdHours))h)")
            try? await activityLog.log(event: ActivityEvent(
                type: .timeMachineStale,
                summary: "Time Machine backup stale (\(Int(hours))h ago)",
                detail: snapshot.destinationName.map { "Destination: \($0)" }
            ))
        } else if let date = snapshot.lastBackupDate {
            Logger.health.info("Time Machine: last backup \(date)")
        }
    }

    private func readTimeMachineStatus() -> TimeMachineSnapshot {
        let result = ShellRunner.run("/usr/bin/tmutil", arguments: ["destinationinfo", "-X"])

        var isConfigured = false
        var destinationName: String?
        var autoBackup = false

        if result.succeeded, let data = result.output.data(using: .utf8) {
            if let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil
            ) as? [String: Any] {
                if let destinations = plist["Destinations"] as? [[String: Any]], let first = destinations.first {
                    isConfigured = true
                    destinationName = first["Name"] as? String
                }
            }
        }

        // Check auto backup
        let autoResult = ShellRunner.run("/usr/bin/defaults", arguments: [
            "read", "/Library/Preferences/com.apple.TimeMachine", "AutoBackup"
        ])
        if autoResult.succeeded {
            autoBackup = autoResult.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        }

        // Get latest backup date
        var lastBackupDate: Date?
        var hoursSince: Double?
        let latestResult = ShellRunner.run("/usr/bin/tmutil", arguments: ["latestbackup"])
        if latestResult.succeeded {
            let path = latestResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            // Path format: /Volumes/Backup/Backups.backupdb/MacName/2024-01-15-120000
            if let dateStr = path.split(separator: "/").last {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                if let date = formatter.date(from: String(dateStr)) {
                    lastBackupDate = date
                    hoursSince = Date().timeIntervalSince(date) / 3600
                }
            }
        }

        // Get backup size
        var backupSizeGB: Double?
        if isConfigured {
            let sizeResult = ShellRunner.run("/usr/bin/tmutil", arguments: ["listbackups"])
            if sizeResult.succeeded {
                let backups = sizeResult.output.split(separator: "\n").filter { !$0.isEmpty }
                // Just count backups as a proxy; actual size would need du which is slow
                if !backups.isEmpty {
                    backupSizeGB = nil // Don't run expensive disk scan
                }
            }
        }

        return TimeMachineSnapshot(
            isConfigured: isConfigured,
            lastBackupDate: lastBackupDate,
            oldestBackupDate: nil,
            backupSizeGB: backupSizeGB,
            destinationName: destinationName,
            autoBackupEnabled: autoBackup,
            hoursSinceLastBackup: hoursSince,
            timestamp: Date()
        )
    }
}
