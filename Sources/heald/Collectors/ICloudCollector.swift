import Foundation
import HealdCore
import ServiceLifecycle
import OSLog

/// Monitors iCloud Drive sync state on ~/Documents.
/// Collects: local vs cloud file counts, evicted dirs, conflicts, bird daemon status.
/// Optionally heals by triggering brctl download for cloud placeholders.
struct ICloudCollector: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    private static let interval: Duration = .seconds(900)
    private static let bootSettle: TimeInterval = 180
    private static let sizeTTL: TimeInterval = 1800
    static let healBatchSize = 50

    func run() async throws {
        var sizeCache = DirectorySizeCache(ttl: Self.sizeTTL)
        var lastHeal: Date?
        try await withGracefulShutdownHandler {
            while true {
                let uptime = ProcessInfo.processInfo.systemUptime
                if !BootStampede.settled(uptime: uptime, minimum: Self.bootSettle) {
                    try await Task.sleep(for: .seconds(30))
                    continue
                }
                let snapshot = collectICloud(sizeCache: &sizeCache)
                await store.updateICloud(snapshot)

                Logger.collector.info("iCloud: \(snapshot.localFiles) local, \(snapshot.cloudFiles) cloud, \(Int(snapshot.syncPercent))% sync, \(snapshot.evictedDirs.count) evicted, \(snapshot.conflicts) conflicts")

                // Never brctl-download Optimize Storage placeholders. That
                // wakes FPCKService and fights the user's iCloud setting.
                let now = Date()
                if ICloudHealPolicy.shouldDownloadPlaceholders(
                    evictedDirCount: snapshot.evictedDirs.count,
                    lastHeal: lastHeal,
                    now: now
                ) {
                    await healEvictedDirs(snapshot: snapshot)
                    lastHeal = now
                }

                // Alert on low sync or evicted dirs
                if snapshot.isEnabled && snapshot.syncPercent < 90 && snapshot.totalFiles > 0 {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .icloudSyncDegraded,
                        summary: "iCloud sync at \(Int(snapshot.syncPercent))% — \(snapshot.cloudFiles) files only in cloud",
                        detail: "Evicted dirs: \(snapshot.evictedDirs.joined(separator: ", "))"
                    ))
                }

                if !snapshot.birdRunning && snapshot.isEnabled {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .icloudDaemonDown,
                        summary: "iCloud daemon (bird) not running",
                        detail: "bird process not found — iCloud sync is stalled"
                    ))
                }

                try await Task.sleep(for: Self.interval)
            }
        } onGracefulShutdown: {
            // Task.sleep throws CancellationError → breaks loop cleanly
        }
    }
}

// MARK: - Collection

private func collectICloud(sizeCache: inout DirectorySizeCache) -> ICloudSnapshot {
    let fm = FileManager.default
    let docsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")

    // 1. iCloud enabled? (check extended attribute)
    let isEnabled = checkICloudEnabled(docsURL: docsURL)

    // 2. Optimize storage setting
    let optimizeStorage = checkOptimizeStorage()

    // 3. Enumerate ~/Documents — count local vs .icloud placeholders
    var localFiles = 0
    var cloudFiles = 0
    var directories = 0
    var evictedDirs: [String] = []
    var conflicts = 0
    let maxDepth = 3

    // Top-level directories
    if let topLevel = try? fm.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: [.isDirectoryKey]) {
        for url in topLevel {
            let name = url.lastPathComponent

            // Skip common exclusions
            if shouldExclude(name) { continue }

            // Check for evicted dirs (.Name.icloud placeholder)
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                let realName = String(name.dropFirst().dropLast(7))
                evictedDirs.append(realName)
                continue
            }

            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                directories += 1
            }
        }
    }

    // File counting with depth limit
    if let enumerator = fm.enumerator(
        at: docsURL,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) {
        for case let fileURL as URL in enumerator {
            // Depth check: count path components relative to docsURL
            let relComponents = fileURL.pathComponents.count - docsURL.pathComponents.count
            if relComponents > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            let name = fileURL.lastPathComponent
            if shouldExclude(name) {
                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isFile else { continue }

            if name == ".DS_Store" { continue }

            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                cloudFiles += 1
            } else if name.contains(" (Conflict)") || name.contains(".conflicted ") {
                conflicts += 1
                localFiles += 1
            } else {
                localFiles += 1
            }
        }
    }

    let totalFiles = localFiles + cloudFiles
    let syncPercent = totalFiles > 0 ? Double(localFiles) * 100.0 / Double(totalFiles) : 100.0

    // Docs size + disk free. Full `du -sk ~/Documents` is a boot stampede;
    // cache 30 min and cap runtime so a huge tree cannot pin a core.
    let docsSize = directorySize(docsURL, cache: &sizeCache)
    let diskFree = diskFreeBytes()

    // Bird daemon
    let birdRunning = isProcessRunning("bird")

    return ICloudSnapshot(
        isEnabled: isEnabled,
        optimizeStorage: optimizeStorage,
        localFiles: localFiles,
        cloudFiles: cloudFiles,
        totalFiles: totalFiles,
        syncPercent: syncPercent,
        directories: directories,
        evictedDirs: evictedDirs,
        conflicts: conflicts,
        docsSize: docsSize,
        diskFree: diskFree,
        birdRunning: birdRunning,
        timestamp: Date()
    )
}

// MARK: - Helpers

private func checkICloudEnabled(docsURL: URL) -> Bool {
    let result = ShellRunner.run("/usr/bin/xattr", arguments: ["-p", "com.apple.file-provider-domain-id", docsURL.path])
    return result.succeeded && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

private func checkOptimizeStorage() -> Bool {
    let result = ShellRunner.run("/usr/bin/defaults", arguments: ["read", "com.apple.bird", "optimize-storage"])
    return result.succeeded && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
}

private func isProcessRunning(_ name: String) -> Bool {
    let result = ShellRunner.run("/usr/bin/pgrep", arguments: ["-x", name])
    return result.succeeded
}

private func directorySize(_ url: URL, cache: inout DirectorySizeCache) -> Int64 {
    cache.bytes(at: url) { url in
        let result = ShellRunner.run(
            "/usr/bin/du",
            arguments: ["-sk", url.path],
            timeoutSeconds: 8
        )
        guard result.succeeded else { return 0 }
        let parts = result.output.split(separator: "\t")
        guard let kb = Int64(parts.first ?? "0") else { return 0 }
        return kb * 1024
    }
}

private func diskFreeBytes() -> Int64 {
    let home = FileManager.default.homeDirectoryForCurrentUser
    guard let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
          let free = values.volumeAvailableCapacityForImportantUsage else { return 0 }
    return free
}

private let excludeNames: Set<String> = [
    ".git", "node_modules", ".next", "__pycache__", ".venv", "venv",
    ".cache", ".Trash", ".DS_Store"
]

private func shouldExclude(_ name: String) -> Bool {
    excludeNames.contains(name) || name.hasSuffix(".pyc") || name.hasPrefix(".tmp")
}

// MARK: - Self-Healing

private func healEvictedDirs(snapshot: ICloudSnapshot) async {
    let fm = FileManager.default
    let docsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")

    for dir in snapshot.evictedDirs {
        let placeholder = docsURL.appendingPathComponent(".\(dir).icloud")
        if fm.fileExists(atPath: placeholder.path) {
            _ = ShellRunner.run("/usr/bin/brctl", arguments: ["download", placeholder.path], timeoutSeconds: 8)
            Logger.collector.info("iCloud heal: downloading evicted dir '\(dir)'")
        }
    }
}
