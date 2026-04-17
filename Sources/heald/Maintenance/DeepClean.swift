import Foundation
import OSLog

/// Deep Clean: system hygiene tasks ported from meister.
/// Runs weekly as part of MaintenanceService.
/// All operations are user-level only (no sudo).
struct DeepClean {
    func run(activityLog: ActivityLog) async {
        Logger.maintenance.info("Deep Clean starting...")
        var totalFreedMB = 0

        totalFreedMB += await cleanUserLogs(activityLog: activityLog)
        totalFreedMB += await cleanOldDownloads(activityLog: activityLog)
        totalFreedMB += await cleanOrphanedPreferences(activityLog: activityLog)
        totalFreedMB += await cleanOldScreenshots(activityLog: activityLog)
        totalFreedMB += await reportIOSBackups(activityLog: activityLog)
        totalFreedMB += await cleanPackageManagerCaches(activityLog: activityLog)
        totalFreedMB += await cleanDevToolCaches(activityLog: activityLog)
        totalFreedMB += await cleanDocker(activityLog: activityLog)
        totalFreedMB += await cleanFontCache(activityLog: activityLog)
        totalFreedMB += await cleanBrokenPlists(activityLog: activityLog)
        totalFreedMB += await cleanBrokenSymlinks(activityLog: activityLog)

        if totalFreedMB > 0 {
            Logger.maintenance.info("Deep Clean: \(totalFreedMB) MB total freed")
            try? await activityLog.log(event: ActivityEvent(
                type: .deepCleanCompleted,
                summary: "Deep Clean: \(totalFreedMB) MB freed"
            ))
        } else {
            Logger.maintenance.info("Deep Clean: system already clean")
        }
    }

    // MARK: - 1. User Logs (>30 days, >50MB)

    private func cleanUserLogs(activityLog: ActivityLog) async -> Int {
        let logDir = "\(NSHomeDirectory())/Library/Logs"
        let sizeMB = dirSizeMB(logDir)
        guard sizeMB > 50 else { return 0 }

        let result = ShellRunner.run("/usr/bin/find", arguments: [
            logDir, "-type", "f", "-mtime", "+30", "-delete"
        ])

        let newSize = dirSizeMB(logDir)
        let freed = sizeMB - newSize
        if freed > 0 {
            Logger.maintenance.info("User logs: freed \(freed) MB")
        }
        return max(freed, 0)
    }

    // MARK: - 2. Old Downloads (DMG/PKG/ZIP >30 days)

    private func cleanOldDownloads(activityLog: ActivityLog) async -> Int {
        let dlDir = "\(NSHomeDirectory())/Downloads"
        let extensions = ["*.dmg", "*.pkg", "*.zip", "*.tar.gz", "*.iso"]

        var args = [dlDir, "-maxdepth", "1", "-type", "f", "("]
        for (i, ext) in extensions.enumerated() {
            if i > 0 { args.append("-o") }
            args.append("-name")
            args.append(ext)
        }
        args.append(")")
        args.append("-mtime")
        args.append("+30")

        let findResult = ShellRunner.run("/usr/bin/find", arguments: args)
        guard findResult.succeeded else { return 0 }

        let files = findResult.output.split(separator: "\n").filter { !$0.isEmpty }
        guard !files.isEmpty else { return 0 }

        var totalBytes: Int64 = 0
        for file in files {
            let path = String(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                totalBytes += size
            }
            try? FileManager.default.removeItem(atPath: path)
        }

        let freedMB = Int(totalBytes / 1_048_576)
        Logger.maintenance.info("Downloads: \(files.count) old installers deleted (\(freedMB) MB)")
        try? await activityLog.log(event: ActivityEvent(
            type: .deepCleanCompleted,
            summary: "Downloads: \(files.count) old installers deleted (\(freedMB) MB)"
        ))
        return freedMB
    }

    // MARK: - 3. Orphaned Preferences

    private func cleanOrphanedPreferences(activityLog: ActivityLog) async -> Int {
        let prefsDir = "\(NSHomeDirectory())/Library/Preferences"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: prefsDir) else { return 0 }

        // Get installed bundle IDs via mdfind
        let mdfindResult = ShellRunner.run("/usr/bin/mdfind", arguments: [
            "kMDItemContentType == 'com.apple.application-bundle'"
        ])
        guard mdfindResult.succeeded else { return 0 }

        let mdlsResult = ShellRunner.run("/usr/bin/mdls", arguments: [
            "-name", "kMDItemCFBundleIdentifier"
        ] + mdfindResult.output.split(separator: "\n").prefix(500).map(String.init))

        var installedIDs = Set<String>()
        for line in mdlsResult.output.split(separator: "\n") {
            if line.contains("kMDItemCFBundleIdentifier") {
                let parts = line.split(separator: "\"")
                if parts.count >= 2 {
                    installedIDs.insert(String(parts[1]))
                }
            }
        }

        var orphanCount = 0
        let plists = files.filter { $0.hasSuffix(".plist") }

        for plist in plists {
            let bundleID = (plist as NSString).deletingPathExtension
            if bundleID.hasPrefix("com.apple.") || bundleID.hasPrefix("Apple.") { continue }
            if bundleID == "loginwindow" || bundleID.hasPrefix("com.heald") { continue }

            if !installedIDs.contains(bundleID) {
                orphanCount += 1
            }
        }

        if orphanCount > 0 {
            Logger.maintenance.info("Orphaned preferences: \(orphanCount) found (not deleting — report only)")
        }
        return 0 // Report-only, no deletion
    }

    // MARK: - 4. Old Screenshots (>30 days)

    private func cleanOldScreenshots(activityLog: ActivityLog) async -> Int {
        let desktopDirs = [
            "\(NSHomeDirectory())/Desktop",
            "\(NSHomeDirectory())/Schreibtisch",
        ]

        var totalFreed = 0
        for dir in desktopDirs {
            guard FileManager.default.fileExists(atPath: dir) else { continue }

            let patterns = ["Screenshot*", "Bildschirmfoto*", "Screen Shot*"]
            for pattern in patterns {
                let result = ShellRunner.run("/usr/bin/find", arguments: [
                    dir, "-maxdepth", "1", "-type", "f",
                    "-name", pattern, "-mtime", "+30"
                ])
                guard result.succeeded else { continue }
                let files = result.output.split(separator: "\n").filter { !$0.isEmpty }
                for file in files {
                    let path = String(file)
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                       let size = attrs[.size] as? Int64 {
                        totalFreed += Int(size / 1_048_576)
                    }
                    try? FileManager.default.removeItem(atPath: path)
                }
            }
        }

        if totalFreed > 0 {
            Logger.maintenance.info("Old screenshots: \(totalFreed) MB freed")
        }
        return totalFreed
    }

    // MARK: - 5. iOS Backups (report only)

    private func reportIOSBackups(activityLog: ActivityLog) async -> Int {
        let backupDir = "\(NSHomeDirectory())/Library/Application Support/MobileSync/Backup"
        guard FileManager.default.fileExists(atPath: backupDir) else { return 0 }

        guard let backups = try? FileManager.default.contentsOfDirectory(atPath: backupDir) else { return 0 }
        let dirs = backups.filter { name in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: "\(backupDir)/\(name)", isDirectory: &isDir) && isDir.boolValue
        }

        if !dirs.isEmpty {
            let totalMB = dirSizeMB(backupDir)
            Logger.maintenance.info("iOS Backups: \(dirs.count) backups (\(totalMB) MB)")
            if totalMB > 10240 {
                try? await activityLog.log(event: ActivityEvent(
                    type: .deepCleanCompleted,
                    summary: "iOS Backups: \(dirs.count) backups using \(totalMB) MB (>10 GB)"
                ))
            }
        }
        return 0 // Report-only
    }

    // MARK: - 6. Package Manager Caches

    private func cleanPackageManagerCaches(activityLog: ActivityLog) async -> Int {
        var freed = 0

        // npm
        let npmDir = "\(NSHomeDirectory())/.npm"
        let npmSize = dirSizeMB(npmDir)
        if npmSize > 50, ShellRunner.findExecutable("npm") != nil {
            let _ = ShellRunner.run(ShellRunner.findExecutable("npm")!, arguments: ["cache", "clean", "--force"])
            freed += npmSize
            Logger.maintenance.info("npm cache: \(npmSize) MB cleaned")
        }

        // yarn
        let yarnDir = "\(NSHomeDirectory())/.yarn/cache"
        let yarnSize = dirSizeMB(yarnDir)
        if yarnSize > 50, let yarn = ShellRunner.findExecutable("yarn") {
            let _ = ShellRunner.run(yarn, arguments: ["cache", "clean"])
            freed += yarnSize
        }

        // pip
        let pipDir = "\(NSHomeDirectory())/Library/Caches/pip"
        let pipSize = dirSizeMB(pipDir)
        if pipSize > 50, let pip = ShellRunner.findExecutable("pip3") {
            let _ = ShellRunner.run(pip, arguments: ["cache", "purge"])
            freed += pipSize
        }

        return freed
    }

    // MARK: - 7. Dev Tool Caches (CocoaPods, SPM, Carthage)

    private func cleanDevToolCaches(activityLog: ActivityLog) async -> Int {
        var freed = 0

        let spmCache = "\(NSHomeDirectory())/.swiftpm/cache"
        let spmSize = dirSizeMB(spmCache)
        if spmSize > 100 {
            try? FileManager.default.removeItem(atPath: spmCache)
            freed += spmSize
            Logger.maintenance.info("SPM cache: \(spmSize) MB cleaned")
        }

        let carthageDir = "\(NSHomeDirectory())/Library/Caches/org.carthage.CarthageKit"
        let carthageSize = dirSizeMB(carthageDir)
        if carthageSize > 100 {
            try? FileManager.default.removeItem(atPath: carthageDir)
            freed += carthageSize
        }

        let podsDir = "\(NSHomeDirectory())/.cocoapods/repos"
        let podsSize = dirSizeMB(podsDir)
        if podsSize > 100 {
            let trunk = "\(podsDir)/trunk"
            try? FileManager.default.removeItem(atPath: trunk)
            freed += podsSize / 2
        }

        return freed
    }

    // MARK: - 8. Docker Cleanup

    private func cleanDocker(activityLog: ActivityLog) async -> Int {
        guard let docker = ShellRunner.findExecutable("docker") else { return 0 }

        // Check if daemon is running
        let info = ShellRunner.run(docker, arguments: ["info"])
        guard info.succeeded else { return 0 }

        let stoppedResult = ShellRunner.run(docker, arguments: [
            "ps", "-aq", "--filter", "status=exited"
        ])
        let stopped = stoppedResult.output.split(separator: "\n").filter { !$0.isEmpty }.count

        let danglingResult = ShellRunner.run(docker, arguments: [
            "images", "-f", "dangling=true", "-q"
        ])
        let dangling = danglingResult.output.split(separator: "\n").filter { !$0.isEmpty }.count

        if stopped > 0 || dangling > 0 {
            let _ = ShellRunner.run(docker, arguments: ["container", "prune", "-f", "--filter", "until=72h"])
            let _ = ShellRunner.run(docker, arguments: ["image", "prune", "-f"])
            let _ = ShellRunner.run(docker, arguments: ["volume", "prune", "-f"])

            Logger.maintenance.info("Docker: \(stopped) containers + \(dangling) images cleaned")
            try? await activityLog.log(event: ActivityEvent(
                type: .deepCleanCompleted,
                summary: "Docker: \(stopped) stopped containers + \(dangling) dangling images cleaned"
            ))
        }
        return 0 // Docker doesn't report freed space easily
    }

    // MARK: - 9. Font & QuickLook Cache

    private func cleanFontCache(activityLog: ActivityLog) async -> Int {
        var freed = 0

        // Font cache
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/atsutil") {
            let _ = ShellRunner.run("/usr/bin/atsutil", arguments: ["databases", "-remove"])
            Logger.maintenance.info("Font cache rebuilt")
        }

        // QuickLook cache
        let qlDir = "\(NSHomeDirectory())/Library/Caches/com.apple.QuickLookDaemon"
        let qlSize = dirSizeMB(qlDir)
        if FileManager.default.fileExists(atPath: qlDir) {
            try? FileManager.default.removeItem(atPath: qlDir)
            freed += qlSize
        }

        // qlmanage reset
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/qlmanage") {
            let _ = ShellRunner.run("/usr/bin/qlmanage", arguments: ["-r"])
        }

        return freed
    }

    // MARK: - 10. Broken Plists

    private func cleanBrokenPlists(activityLog: ActivityLog) async -> Int {
        let prefsDir = "\(NSHomeDirectory())/Library/Preferences"
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: prefsDir) else { return 0 }

        var brokenCount = 0
        for file in files where file.hasSuffix(".plist") && !file.hasPrefix("com.apple.") {
            let path = "\(prefsDir)/\(file)"
            let result = ShellRunner.run("/usr/bin/plutil", arguments: ["-lint", path])
            if !result.succeeded {
                brokenCount += 1
                Logger.maintenance.warning("Broken plist: \(file)")
            }
        }

        if brokenCount > 0 {
            Logger.maintenance.info("Broken plists: \(brokenCount) found (non-Apple)")
        }
        return 0
    }

    // MARK: - 11. Broken Symlinks

    private func cleanBrokenSymlinks(activityLog: ActivityLog) async -> Int {
        let searchDirs = [
            "\(NSHomeDirectory())/Library/LaunchAgents",
            "/usr/local/bin",
        ]

        var brokenCount = 0
        for dir in searchDirs {
            let result = ShellRunner.run("/usr/bin/find", arguments: [
                dir, "-maxdepth", "1", "-type", "l"
            ])
            guard result.succeeded else { continue }

            for line in result.output.split(separator: "\n") {
                let path = String(line)
                // Check if symlink target exists
                if !FileManager.default.fileExists(atPath: path) {
                    brokenCount += 1
                    Logger.maintenance.warning("Broken symlink: \(path)")
                }
            }
        }

        if brokenCount > 0 {
            try? await activityLog.log(event: ActivityEvent(
                type: .deepCleanCompleted,
                summary: "\(brokenCount) broken symlinks found"
            ))
        }
        return 0
    }

    // MARK: - Helpers

    private func dirSizeMB(_ path: String) -> Int {
        guard FileManager.default.fileExists(atPath: path) else { return 0 }
        let result = ShellRunner.run("/usr/bin/du", arguments: ["-sm", path])
        guard result.succeeded else { return 0 }
        return Int(result.output.split(separator: "\t").first ?? "0") ?? 0
    }
}
