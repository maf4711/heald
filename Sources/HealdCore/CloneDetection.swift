import Foundation

/// Outcome of checking a stored `~/.heald/device.json` against the Mac it is running on.
public enum IdentityDecision: Equatable, Sendable {
    /// The record belongs to this Mac (or cannot be checked) — use it as is.
    case keep
    /// The record was enrolled on another Mac (Migration Assistant, backup restore, sync) — re-enroll.
    case reenroll
}

/// Detects a `~/.heald` copied from another Mac and moves its per-device state aside (issue #18).
public enum CloneDetection {
    /// Decide whether a stored device record still belongs to this Mac.
    ///
    /// - `currentHardwareUUID == nil` (ioreg failed): `.keep`. We never rotate identity on a failed probe;
    ///   the check runs again on the next start.
    /// - Stored `hardwareUUID` present: `.reenroll` iff it differs (case-insensitive) from the current one.
    /// - Stored `hardwareUUID` nil (record from an enroll where ioreg failed, or hand-written): enroll derives
    ///   `deviceId` from the hardware UUID whenever one is available, so a `deviceId` equal to the current
    ///   UUID proves the record was made here → `.keep`. A different `deviceId` is treated as a mismatch →
    ///   `.reenroll`. Trade-off: a genuine record enrolled while ioreg was failing (random `deviceId`) is
    ///   re-enrolled once; that backfills `hardwareUUID`, so it cannot repeat. We accept one extra
    ///   re-enroll over silently reporting as another Mac.
    public static func decide(
        storedHardwareUUID: String?,
        storedDeviceId: String,
        currentHardwareUUID: String?
    ) -> IdentityDecision {
        guard let current = normalized(currentHardwareUUID) else { return .keep }
        if let stored = normalized(storedHardwareUUID) {
            return stored == current ? .keep : .reenroll
        }
        return normalized(storedDeviceId) == current ? .keep : .reenroll
    }

    /// Per-device files, relative to the heald root (`~/.heald`), that a cloned Mac must not reuse.
    /// History that is never re-sent (`data/activity.ndjson`, `data/metrics.db`, `data/cli-maintain.db`)
    /// stays in place: with the cursors moved, CloudPusher and SyslogSink restart at EOF.
    public static let perDeviceFiles: [String] = [
        "device.json",                  // identity + bearer token of the source Mac
        "spotlight_fixed",              // one-time Spotlight fix marker for the source Mac's /Applications
        "data/heal_reports.ndjson",     // HealReportOutbox: source Mac's undelivered heal reports
        "data/heal_report_cursor",      // HealReportOutbox delivery cursor
        "data/findings.json",           // FindingsStore: source Mac's error picture (machineId inside)
        "data/cloud_push_cursor",       // CloudPusher byte offset into activity.ndjson
        "data/siem_cursor",             // SyslogSink byte offset into activity.ndjson
        "data/error_scanner_seen.json", // SystemErrorScanner dedupe state for source Mac's reports
        "data/crash_loop.json",         // CrashLoopQuarantine crash timestamps of source Mac's apps
        "data/self_heal.json",          // SelfHealOrchestrator status snapshot (shown by doctor)
        "data/sudo_ticket_ok",          // SudoTicket marker — sudoers lives on the source Mac
        "data/auto_update.json",        // AutoUpdateService last status of the source Mac
        "data/fleet_ack.ndjson",        // FleetAck log, every line tagged with the source host
        "data/meister_bridge.json",     // MeisterBridgeRunner status snapshot
    ]

    /// `.cloned-<first 8 safe chars of deviceId>-<UTC yyyyMMdd-HHmmss>`.
    public static func archiveDirectoryName(sourceDeviceId: String, now: Date) -> String {
        "\(archivePrefix)\(idPrefix(sourceDeviceId))-\(stamp(now))"
    }

    public static let archivePrefix = ".cloned-"

    /// First 8 filename-safe characters of a device id (the id comes from a file — never trust it in a path).
    public static func idPrefix(_ deviceId: String) -> String {
        let safe = deviceId.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        let p = String(String.UnicodeScalarView(safe).prefix(8))
        return p.isEmpty ? "unknown" : p
    }

    public struct Relocation: Equatable, Sendable {
        public let archiveDirectory: URL
        /// Paths (relative to the heald root) that were moved.
        public let moved: [String]
    }

    /// Move every existing per-device file under `healdDir` into `healdDir/data/.cloned-…/` (never deletes).
    /// Files keep their basenames; nothing is moved if none exist, but the archive directory is still created
    /// so the event leaves a trace.
    public static func relocate(
        healdDir: URL,
        sourceDeviceId: String,
        now: Date = Date(),
        files: [String] = perDeviceFiles,
        fileManager fm: FileManager = .default
    ) throws -> Relocation {
        let dataDir = healdDir.appendingPathComponent("data")
        let base = archiveDirectoryName(sourceDeviceId: sourceDeviceId, now: now)
        var archive = dataDir.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: archive.path) {
            archive = dataDir.appendingPathComponent("\(base)-\(n)")
            n += 1
        }
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)

        var moved: [String] = []
        for rel in files {
            let src = healdDir.appendingPathComponent(rel)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.moveItem(at: src, to: archive.appendingPathComponent(src.lastPathComponent))
            moved.append(rel)
        }
        return Relocation(archiveDirectory: archive, moved: moved)
    }

    private static func normalized(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t.uppercased()
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }
}
