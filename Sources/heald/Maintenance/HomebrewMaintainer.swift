import Foundation
import OSLog

/// Homebrew update/upgrade/cleanup, Mac App Store updates, MAS→Brew migration, Office updates.
struct HomebrewMaintainer {
    private let brewPath: String?

    init() {
        self.brewPath = ShellRunner.findExecutable("brew")
    }

    // MARK: - Homebrew Update & Upgrade

    func updateAndUpgrade(activityLog: ActivityLog) async throws {
        guard let brew = brewPath else {
            Logger.maintenance.info("Homebrew not found — skipping")
            return
        }

        Logger.maintenance.info("Running brew update...")
        var result = ShellRunner.run(brew, arguments: ["update"])

        if !result.succeeded {
            Logger.maintenance.warning("brew update failed, trying unshallow...")
            let repoResult = ShellRunner.run(brew, arguments: ["--repo"])
            if repoResult.succeeded {
                let repoPath = repoResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = ShellRunner.run("/usr/bin/git", arguments: ["-C", repoPath, "fetch", "--unshallow"])
                result = ShellRunner.run(brew, arguments: ["update"])
            }
            if !result.succeeded {
                throw MaintenanceError.failed("brew update failed: \(result.errorOutput)")
            }
        }

        // Formulae
        Logger.maintenance.info("Running brew upgrade...")
        let formulaeResult = ShellRunner.run(brew, arguments: ["upgrade"])
        let formulaeOutput = formulaeResult.output

        // Casks
        Logger.maintenance.info("Running brew upgrade --cask...")
        let caskResult = ShellRunner.run(brew, arguments: ["upgrade", "--cask"])
        let caskOutput = caskResult.output

        // Cleanup
        _ = ShellRunner.run(brew, arguments: ["cleanup", "-s"])

        let detail = [formulaeOutput, caskOutput]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n---\n")

        try await activityLog.log(event: ActivityEvent(
            type: .brewUpgrade,
            summary: "Homebrew: update + upgrade + cleanup completed",
            detail: detail.isEmpty ? nil : String(detail.prefix(1000))
        ))

        Logger.maintenance.info("Homebrew maintenance complete")
    }

    // MARK: - Mac App Store

    func updateMAS(activityLog: ActivityLog) async throws {
        guard let mas = ShellRunner.findExecutable("mas") else {
            Logger.maintenance.info("mas CLI not found — skipping App Store updates")
            return
        }

        let outdated = ShellRunner.run(mas, arguments: ["outdated"])
        let outdatedText = outdated.output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard outdated.succeeded, !outdatedText.isEmpty else {
            Logger.maintenance.info("App Store: all apps up to date")
            return
        }

        let count = outdatedText.split(separator: "\n").count
        Logger.maintenance.info("App Store: \(count) updates available, upgrading...")

        let result = ShellRunner.run(mas, arguments: ["upgrade"])

        let summary = result.succeeded
            ? "App Store: \(count) apps updated"
            : "App Store: upgrade failed (exit \(result.exitCode))"

        try await activityLog.log(event: ActivityEvent(
            type: .masUpdate,
            summary: summary,
            detail: outdatedText
        ))

        if !result.succeeded {
            throw MaintenanceError.failed(summary)
        }
    }

    // MARK: - MAS → Homebrew Migration

    func migrateMASApps(activityLog: ActivityLog) async throws {
        guard let brew = brewPath else { return }

        let migrations: [(app: String, cask: String)] = [
            ("WhatsApp.app", "whatsapp"),
            ("Google Chrome.app", "google-chrome"),
            ("Firefox.app", "firefox"),
            ("Slack.app", "slack"),
            ("Zoom.us.app", "zoom"),
            ("Microsoft Word.app", "microsoft-word"),
            ("Microsoft Excel.app", "microsoft-excel"),
            ("Microsoft PowerPoint.app", "microsoft-powerpoint"),
            ("Visual Studio Code.app", "visual-studio-code"),
            ("Spotify.app", "spotify"),
            ("Telegram.app", "telegram"),
            ("VLC.app", "vlc"),
            ("OneDrive.app", "onedrive"),
            ("Messenger.app", "messenger"),
        ]

        // Known duplicates to remove
        let duplicates = ["WhatsApp 2.app"]

        var migrated = 0

        for dup in duplicates {
            let path = "/Applications/\(dup)"
            if FileManager.default.fileExists(atPath: path) {
                try? FileManager.default.removeItem(atPath: path)
                migrated += 1
                try await activityLog.log(event: ActivityEvent(
                    type: .appMigration,
                    summary: "Removed duplicate: \(dup)"
                ))
            }
        }

        for (app, cask) in migrations {
            let appPath = "/Applications/\(app)"
            let receiptPath = "\(appPath)/Contents/_MASReceipt"

            guard FileManager.default.fileExists(atPath: appPath),
                  FileManager.default.fileExists(atPath: receiptPath) else { continue }

            // Verify cask exists
            let infoResult = ShellRunner.run(brew, arguments: ["info", "--cask", cask])
            guard infoResult.succeeded else { continue }

            Logger.maintenance.info("Migrating \(app) from MAS to Homebrew (\(cask))...")

            // Kill the app
            let appName = (app as NSString).deletingPathExtension
            _ = ShellRunner.run("/usr/bin/pkill", arguments: ["-f", appName])
            try await Task.sleep(for: .seconds(2))

            // Remove MAS version
            try? FileManager.default.removeItem(atPath: appPath)

            // Install via Homebrew
            let installResult = ShellRunner.run(brew, arguments: ["install", "--cask", cask])

            try await activityLog.log(event: ActivityEvent(
                type: .appMigration,
                summary: installResult.succeeded
                    ? "Migrated \(app) from App Store to Homebrew"
                    : "Migration failed for \(app)",
                beforeState: "MAS",
                afterState: installResult.succeeded ? "Homebrew" : "FAILED"
            ))

            if installResult.succeeded { migrated += 1 }
        }

        if migrated > 0 {
            Logger.maintenance.info("App migration: \(migrated) apps processed")
        }
    }

    // MARK: - Microsoft Office Updates

    func updateOffice(activityLog: ActivityLog) async throws {
        let msUpdatePath = "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app/Contents/MacOS/msupdate"

        guard FileManager.default.isExecutableFile(atPath: msUpdatePath) else {
            Logger.maintenance.info("MS AutoUpdate not found — skipping")
            return
        }

        Logger.maintenance.info("Checking Microsoft Office updates...")
        let result = ShellRunner.run(msUpdatePath, arguments: ["--install", "--wait", "600"])

        let summary: String
        if result.succeeded && result.output.contains("No updates") {
            summary = "Office: up to date"
        } else if result.succeeded {
            summary = "Office: updates installed"
        } else {
            summary = "Office: update failed (exit \(result.exitCode))"
        }

        try await activityLog.log(event: ActivityEvent(
            type: .officeUpdate,
            summary: summary,
            detail: result.output.isEmpty ? nil : String(result.output.prefix(500))
        ))

        if !result.succeeded {
            throw MaintenanceError.failed(summary)
        }
    }
}

enum MaintenanceError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let msg): return msg
        }
    }
}
