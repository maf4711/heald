import Foundation
import OSLog

/// NDJSON activity log for system events (LOG-01, LOG-04).
/// Each line is a self-contained JSON object — human-grepable.
/// Supports byte-offset cursor reads for CloudPusher (no re-send of old lines).
actor ActivityLog {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    private let maxSizeBytes: Int64

    /// Path to the NDJSON file (for external cursor storage).
    var path: String { fileURL.path }

    init(path: String, maxSizeMB: Int = 50) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        fileURL = URL(fileURLWithPath: path)
        maxSizeBytes = Int64(maxSizeMB) * 1_048_576

        // Create file if it doesn't exist
        if !FileManager.default.fileExists(atPath: path) {
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        fileHandle = try FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()

        Logger.storage.info("ActivityLog opened at \(path)")
    }

    // MARK: - Log Events

    func log(event: ActivityEvent) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(event)
        guard var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"

        fileHandle?.write(Data(line.utf8))

        Logger.storage.info("Activity: \(event.type.rawValue) — \(event.summary)")
    }

    // MARK: - Cursor reads (dashboard push)

    /// Current end-of-file byte offset (after flush).
    func endOffset() throws -> UInt64 {
        try flushWriters()
        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attrs[.size] as? UInt64) ?? (attrs[.size] as? NSNumber)?.uint64Value ?? 0
    }

    /// Read complete NDJSON lines starting at `offset`. Incomplete trailing line is not consumed.
    /// If the file was rotated and is smaller than `offset`, reading restarts at 0.
    func readEvents(since offset: UInt64, limit: Int = 50) throws -> ActivityReadBatch {
        try flushWriters()

        let size = try endOffset()
        var pos = offset
        if pos > size {
            // Rotation or truncate — resync to start of new file
            Logger.storage.info("ActivityLog cursor \(offset) past EOF \(size) — reset to 0")
            pos = 0
        }
        if pos >= size || limit <= 0 {
            return ActivityReadBatch(events: [], nextOffset: size)
        }

        let readHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? readHandle.close() }
        try readHandle.seek(toOffset: pos)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var events: [ActivityEvent] = []
        var buffer = Data()
        var currentPos = pos
        let maxReadBytes = 512 * 1024

        while events.count < limit {
            let remainingBudget = maxReadBytes - buffer.count
            if remainingBudget <= 0 { break }

            let chunk = try readHandle.read(upToCount: min(16_384, remainingBudget)) ?? Data()
            if chunk.isEmpty {
                // EOF — drop incomplete trailing line (keep currentPos before it)
                break
            }
            buffer.append(chunk)

            while events.count < limit {
                guard let nl = buffer.firstIndex(of: 0x0A) else { break }
                let lineLen = nl + 1 // include newline in offset advance
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                currentPos += UInt64(lineLen)

                guard !lineData.isEmpty else { continue }
                if let event = try? decoder.decode(ActivityEvent.self, from: lineData) {
                    events.append(event)
                }
                // Skip corrupt lines but still advance cursor (avoid stuck)
            }

            if chunk.count < 16_384 && buffer.firstIndex(of: 0x0A) == nil {
                // Likely at EOF with partial line
                break
            }
        }

        return ActivityReadBatch(events: events, nextOffset: currentPos)
    }

    private func flushWriters() throws {
        try fileHandle?.synchronize()
    }

    // MARK: - Rotation (LOG-03)

    func rotateIfNeeded() throws {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int64,
              size > maxSizeBytes else { return }

        fileHandle?.closeFile()

        let rotatedPath = fileURL.path + ".old"
        // Remove previous rotated file
        try? FileManager.default.removeItem(atPath: rotatedPath)
        try FileManager.default.moveItem(atPath: fileURL.path, toPath: rotatedPath)

        // Create fresh file
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: fileURL)

        Logger.storage.info("ActivityLog rotated (\(size / 1_048_576)MB)")
    }

    deinit {
        fileHandle?.closeFile()
    }
}

/// Result of a cursor-based activity read.
struct ActivityReadBatch: Sendable {
    let events: [ActivityEvent]
    /// Byte offset to pass as `since` on the next successful push.
    let nextOffset: UInt64
}

// MARK: - Event Types

struct ActivityEvent: Codable, Sendable {
    let timestamp: Date
    let type: EventType
    let summary: String
    let detail: String?
    let beforeState: String?
    let afterState: String?
    let aiGenerated: Bool

    init(
        type: EventType,
        summary: String,
        detail: String? = nil,
        beforeState: String? = nil,
        afterState: String? = nil,
        aiGenerated: Bool = false
    ) {
        self.timestamp = Date()
        self.type = type
        self.summary = summary
        self.detail = detail
        self.beforeState = beforeState
        self.afterState = afterState
        self.aiGenerated = aiGenerated
    }
}

enum EventType: String, Codable, Sendable {
    case processKilled = "process_killed"
    case processRestarted = "process_restarted"
    case dnsFlushed = "dns_flushed"
    case orphanedPlistFound = "orphaned_plist_found"
    case brokenPlistFound = "broken_plist_found"
    case swapSpike = "swap_spike"
    case diskWarning = "disk_warning"
    case smartFailure = "smart_failure"
    case crashDetected = "crash_detected"
    case healingAttempt = "healing_attempt"
    case healingSuccess = "healing_success"
    case healingFailed = "healing_failed"
    case daemonStarted = "daemon_started"
    case daemonStopped = "daemon_stopped"
    case retentionPurge = "retention_purge"

    // Maintenance (from meister2026.sh)
    case brewUpgrade = "brew_upgrade"
    case masUpdate = "mas_update"
    case appMigration = "app_migration"
    case officeUpdate = "office_update"
    case cacheCleanup = "cache_cleanup"
    case trashCleanup = "trash_cleanup"
    case largeFileFound = "large_file_found"
    case clamavScan = "clamav_scan"
    case modelUpdate = "model_update"
    case spotlightFix = "spotlight_fix"
    case periodicMaintenance = "periodic_maintenance"
    case lmStudioSync = "lm_studio_sync"
    case maintenanceStarted = "maintenance_started"
    case maintenanceCompleted = "maintenance_completed"

    // Self-Healing
    case selfHealed = "self_healed"
    case aiFixBlocked = "ai_fix_blocked"

    // Benchmark
    case benchmarkStarted = "benchmark_started"
    case benchmarkCompleted = "benchmark_completed"

    // Thermal
    case thermalThrottling = "thermal_throttling"

    // iCloud
    case icloudSyncDegraded = "icloud_sync_degraded"
    case icloudDaemonDown = "icloud_daemon_down"

    // Security
    case fileVaultDisabled = "filevault_disabled"
    case firewallDisabled = "firewall_disabled"
    case ssdWearWarning = "ssd_wear_warning"

    // New collectors/checks
    case gpuHighUsage = "gpu_high_usage"
    case bluetoothLowBattery = "bluetooth_low_battery"
    case wifiPoorSignal = "wifi_poor_signal"
    case memoryLeakDetected = "memory_leak_detected"
    case loginItemsScan = "login_items_scan"
    case timeMachineStale = "time_machine_stale"
    case timeMachineNotConfigured = "time_machine_not_configured"
    case focusChanged = "focus_changed"
    case diskIOAnomaly = "disk_io_anomaly"
    case brewVulnerability = "brew_vulnerability"

    // Security (meister port)
    case gatekeeperDisabled = "gatekeeper_disabled"
    case sipDisabled = "sip_disabled"
    case xprotectStale = "xprotect_stale"
    case suspiciousPersistence = "suspicious_persistence"
    case tccOrphanedPermission = "tcc_orphaned_permission"

    // Spotlight + iCloud (meister port)
    case spotlightStuck = "spotlight_stuck"
    case icloudGhostFolders = "icloud_ghost_folders"
    case icloudCorruptStubs = "icloud_corrupt_stubs"

    // Git
    case gitReposDirty = "git_repos_dirty"

    // Deep Clean
    case deepCleanCompleted = "deep_clean_completed"

    // System log / fault scanner
    case systemFault = "system_fault"
}
