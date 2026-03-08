import Foundation
import OSLog

/// NDJSON activity log for system events (LOG-01, LOG-04).
/// Each line is a self-contained JSON object — human-grepable.
actor ActivityLog {
    private let fileURL: URL
    private var fileHandle: FileHandle?
    private let maxSizeBytes: Int64

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
}
