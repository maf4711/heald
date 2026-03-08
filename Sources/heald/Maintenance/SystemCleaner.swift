import Foundation
import OSLog

/// Cache cleaning, Trash cleanup, Large File detection, Xcode DerivedData,
/// periodic maintenance, Spotlight fix for MAS apps.
struct SystemCleaner {
    private let largeFileSizeMB: Int = 1000

    // MARK: - Cache Cleaning

    func cleanCaches(activityLog: ActivityLog) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let userCachePath = "\(home)/Library/Caches"

        var freedBytes: UInt64 = 0

        // User caches
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: userCachePath) {
            for item in contents {
                let itemPath = "\(userCachePath)/\(item)"
                if let size = fileSize(atPath: itemPath) {
                    freedBytes += size
                }
                try? FileManager.default.removeItem(atPath: itemPath)
            }
        }

        let freedMB = freedBytes / 1_048_576
        let summary = "Cleaned user caches (\(freedMB) MB freed)"

        try await activityLog.log(event: ActivityEvent(
            type: .cacheCleanup,
            summary: summary
        ))

        Logger.maintenance.info("\(summary)")

        // Note: System caches (/Library/Caches, /System/Library/Caches) require sudo
        // which is not available in LaunchAgent context
        Logger.maintenance.info("System caches require sudo — skipped (LaunchAgent context)")
    }

    // MARK: - Trash Cleanup

    func emptyTrash(activityLog: ActivityLog) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let trashPath = "\(home)/.Trash"

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: trashPath),
              !contents.isEmpty else {
            Logger.maintenance.info("Trash already empty")
            return
        }

        var freedBytes: UInt64 = 0
        let itemCount = contents.count

        for item in contents {
            let itemPath = "\(trashPath)/\(item)"
            if let size = fileSize(atPath: itemPath) {
                freedBytes += size
            }
            try? FileManager.default.removeItem(atPath: itemPath)
        }

        let freedMB = freedBytes / 1_048_576
        let summary = "Emptied Trash: \(itemCount) items (\(freedMB) MB freed)"

        try await activityLog.log(event: ActivityEvent(
            type: .trashCleanup,
            summary: summary
        ))

        Logger.maintenance.info("\(summary)")
    }

    // MARK: - Xcode DerivedData

    func cleanXcodeDerivedData(activityLog: ActivityLog) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let derivedDataPath = "\(home)/Library/Developer/Xcode/DerivedData"

        guard FileManager.default.fileExists(atPath: derivedDataPath) else {
            Logger.maintenance.info("No Xcode DerivedData found")
            return
        }

        let sizeBefore = fileSize(atPath: derivedDataPath) ?? 0
        try? FileManager.default.removeItem(atPath: derivedDataPath)

        let freedMB = sizeBefore / 1_048_576
        let summary = "Cleaned Xcode DerivedData (\(freedMB) MB freed)"

        try await activityLog.log(event: ActivityEvent(
            type: .cacheCleanup,
            summary: summary
        ))

        Logger.maintenance.info("\(summary)")
    }

    // MARK: - Large File Detection

    func findLargeFiles(activityLog: ActivityLog) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let thresholdBytes = UInt64(largeFileSizeMB) * 1_048_576

        // Use find command for efficiency
        let result = ShellRunner.run(
            "/usr/bin/find", arguments: [home, "-xdev", "-type", "f", "-size", "+\(largeFileSizeMB)M"]
        )

        guard result.succeeded else { return }

        let files = result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        guard !files.isEmpty else {
            Logger.maintenance.info("No files larger than \(largeFileSizeMB) MB found")
            return
        }

        // Get sizes
        var fileList: [(path: String, sizeMB: UInt64)] = []
        for file in files.prefix(50) { // Limit to top 50
            if let size = fileSize(atPath: file), size >= thresholdBytes {
                fileList.append((file, size / 1_048_576))
            }
        }

        fileList.sort { $0.sizeMB > $1.sizeMB }

        let detail = fileList.prefix(20).map { "\($0.sizeMB) MB — \($0.path)" }.joined(separator: "\n")

        try await activityLog.log(event: ActivityEvent(
            type: .largeFileFound,
            summary: "\(fileList.count) files larger than \(largeFileSizeMB) MB found",
            detail: detail
        ))

        Logger.maintenance.info("Found \(fileList.count) large files (>\(largeFileSizeMB) MB)")
    }

    // MARK: - Periodic Maintenance

    func runPeriodicMaintenance(activityLog: ActivityLog) async throws {
        // periodic daily/weekly/monthly requires root
        // As LaunchAgent, we try without sudo — may fail silently
        let result = ShellRunner.run("/usr/sbin/periodic", arguments: ["daily", "weekly", "monthly"])

        if result.succeeded {
            try await activityLog.log(event: ActivityEvent(
                type: .periodicMaintenance,
                summary: "Ran periodic maintenance (daily/weekly/monthly)"
            ))
            Logger.maintenance.info("Periodic maintenance completed")
        } else {
            // Expected to fail without sudo in LaunchAgent context
            Logger.maintenance.info("Periodic maintenance requires root — skipped")
        }
    }

    // MARK: - Spotlight Fix for MAS Apps (one-time)

    func fixSpotlightForMASApps(activityLog: ActivityLog) async {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let markerPath = "\(home)/.heald/spotlight_fixed"

        guard !FileManager.default.fileExists(atPath: markerPath) else { return }

        Logger.maintenance.info("Indexing MAS apps for Spotlight (one-time)...")

        let appsDir = "/Applications"
        guard let apps = try? FileManager.default.contentsOfDirectory(atPath: appsDir) else { return }

        var indexed = 0
        for app in apps where app.hasSuffix(".app") {
            let receiptPath = "\(appsDir)/\(app)/Contents/_MASReceipt"
            guard FileManager.default.fileExists(atPath: receiptPath) else { continue }

            _ = ShellRunner.run("/usr/bin/mdimport", arguments: ["\(appsDir)/\(app)"])
            indexed += 1
        }

        // Create marker
        let markerDir = (markerPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: markerDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: markerPath, contents: nil)

        if indexed > 0 {
            try? await activityLog.log(event: ActivityEvent(
                type: .spotlightFix,
                summary: "Spotlight index rebuilt for \(indexed) MAS apps"
            ))
        }

        Logger.maintenance.info("Spotlight fix complete: \(indexed) MAS apps indexed")
    }

    // MARK: - Helpers

    private func fileSize(atPath path: String) -> UInt64? {
        // For directories, use du
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }

        if isDir.boolValue {
            let result = ShellRunner.run("/usr/bin/du", arguments: ["-sk", path])
            guard result.succeeded,
                  let sizeKB = UInt64(result.output.split(separator: "\t").first ?? "") else { return nil }
            return sizeKB * 1024
        }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64 else { return nil }
        return size
    }
}
