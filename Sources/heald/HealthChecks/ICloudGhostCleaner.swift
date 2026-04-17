import Foundation
import OSLog

/// Detects and cleans iCloud sync artifacts:
/// - Ghost folders in HOME (empty dirs created by iCloud sync)
/// - Corrupt iCloud stubs (hardlink count 65535, size 0)
/// - bird daemon CPU monitoring
struct ICloudGhostCleaner {
    /// Known directories that should exist in HOME
    private let knownHomeDirs: Set<String> = [
        ".Trash", ".cache", ".config", ".local", ".ssh", ".gnupg",
        ".heald", ".claude", ".ollama", ".nvm", ".npm", ".docker",
        ".gradle", ".cargo", ".rustup",
        "Desktop", "Documents", "Downloads", "Movies", "Music",
        "Pictures", "Public", "Library", "Applications", "Sites",
        "Developer", "go", "miniforge3", "Parallels",
    ]

    func check(activityLog: ActivityLog) async {
        await checkGhostFolders(activityLog: activityLog)
        await checkCorruptStubs(activityLog: activityLog)
        await checkBirdDaemon(activityLog: activityLog)
    }

    // MARK: - Ghost Folders

    private func checkGhostFolders(activityLog: ActivityLog) async {
        let home = NSHomeDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: home) else { return }

        var ghostCount = 0
        for entry in entries {
            if knownHomeDirs.contains(entry) { continue }
            if entry.hasPrefix(".") { continue } // Skip all hidden files

            let fullPath = "\(home)/\(entry)"
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }

            // Check if directory is truly empty (ignoring .DS_Store and .localized)
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: fullPath) {
                let meaningful = contents.filter { $0 != ".DS_Store" && $0 != ".localized" }
                if meaningful.isEmpty {
                    ghostCount += 1
                    Logger.health.warning("iCloud ghost folder: ~/\(entry)")
                }
            }
        }

        if ghostCount > 0 {
            try? await activityLog.log(event: ActivityEvent(
                type: .icloudGhostFolders,
                summary: "\(ghostCount) empty ghost folders in HOME (likely iCloud artifacts)"
            ))
        }
    }

    // MARK: - Corrupt Stubs (65535 hardlinks)

    private func checkCorruptStubs(activityLog: ActivityLog) async {
        let scanPaths = [
            "\(NSHomeDirectory())/Documents",
            "\(NSHomeDirectory())/Desktop",
            "\(NSHomeDirectory())/Library/Mobile Documents/com~apple~CloudDocs",
        ]

        var corruptCount = 0

        for scanPath in scanPaths {
            guard FileManager.default.fileExists(atPath: scanPath) else { continue }

            // Use find to detect files with hardlink count 65535 and size 0
            let result = ShellRunner.run("/usr/bin/find", arguments: [
                scanPath, "-maxdepth", "3",
                "-type", "f", "-links", "65535", "-empty"
            ])

            if result.succeeded {
                let stubs = result.output.split(separator: "\n").filter { !$0.isEmpty }
                corruptCount += stubs.count

                for stub in stubs.prefix(10) {
                    Logger.health.warning("Corrupt iCloud stub: \(stub)")
                }
            }
        }

        if corruptCount > 0 {
            Logger.health.warning("Found \(corruptCount) corrupt iCloud stubs (links=65535, size=0)")
            try? await activityLog.log(event: ActivityEvent(
                type: .icloudCorruptStubs,
                summary: "\(corruptCount) corrupt iCloud stubs found (hardlink=65535, size=0)",
                detail: "These are broken iCloud placeholder files that failed to sync"
            ))
        }
    }

    // MARK: - bird Daemon Health

    private func checkBirdDaemon(activityLog: ActivityLog) async {
        let result = ShellRunner.run("/bin/ps", arguments: ["-eo", "%cpu,comm"])
        guard result.succeeded else { return }

        var birdCPU: Double = 0
        for line in result.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("/bird") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let cpu = parts.first.flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) {
                    birdCPU = cpu
                }
            }
        }

        if birdCPU > 50 {
            Logger.health.warning("iCloud bird daemon at \(Int(birdCPU))% CPU — may be stuck")
            try? await activityLog.log(event: ActivityEvent(
                type: .icloudDaemonDown,
                summary: "iCloud bird daemon at \(Int(birdCPU))% CPU — may need restart"
            ))
        }
    }
}
