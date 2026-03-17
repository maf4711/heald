import Foundation
import ServiceLifecycle
import OSLog

/// Monitors iCloud Drive sync state on ~/Documents.
/// Collects: local vs cloud file counts, evicted dirs, conflicts, bird daemon status.
/// Optionally heals by triggering brctl download for cloud placeholders.
struct ICloudCollector: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    private static let interval: Duration = .seconds(300)  // 5 min — iCloud state changes slowly
    static let healBatchSize = 50

    func run() async throws {
        try await withGracefulShutdownHandler {
            while true {
                let snapshot = collectICloud()
                await store.updateICloud(snapshot)

                Logger.collector.info("iCloud: \(snapshot.localFiles) local, \(snapshot.cloudFiles) cloud, \(Int(snapshot.syncPercent))% sync, \(snapshot.evictedDirs.count) evicted, \(snapshot.conflicts) conflicts")

                // Self-heal: download cloud placeholders
                if snapshot.cloudFiles > 0 {
                    await healCloudFiles(snapshot: snapshot)
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

private func collectICloud() -> ICloudSnapshot {
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

    // Docs size + disk free
    let docsSize = directorySize(docsURL)
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

private func directorySize(_ url: URL) -> Int64 {
    let result = ShellRunner.run("/usr/bin/du", arguments: ["-sk", url.path])
    guard result.succeeded else { return 0 }
    let parts = result.output.split(separator: "\t")
    guard let kb = Int64(parts.first ?? "0") else { return 0 }
    return kb * 1024
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

private func healCloudFiles(snapshot: ICloudSnapshot) async {
    let fm = FileManager.default
    let docsURL = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")

    // Download evicted top-level dirs
    for dir in snapshot.evictedDirs {
        let placeholder = docsURL.appendingPathComponent(".\(dir).icloud")
        if fm.fileExists(atPath: placeholder.path) {
            _ = ShellRunner.run("/usr/bin/brctl", arguments: ["download", placeholder.path])
            Logger.collector.info("iCloud heal: downloading evicted dir '\(dir)'")
        }
    }

    // Download cloud file placeholders (batched) via find + brctl
    let findResult = ShellRunner.run("/usr/bin/find", arguments: [
        docsURL.path, "-maxdepth", "3", "-name", ".*.icloud", "-print"
    ])
    guard findResult.succeeded else { return }

    var downloaded = 0
    for line in findResult.output.split(separator: "\n") {
        guard downloaded < ICloudCollector.healBatchSize else { break }
        let path = String(line)
        guard !path.isEmpty else { continue }
        _ = ShellRunner.run("/usr/bin/brctl", arguments: ["download", path])
        downloaded += 1
    }

    if downloaded > 0 {
        Logger.collector.info("iCloud heal: triggered download for \(downloaded) cloud files")
    }
}
