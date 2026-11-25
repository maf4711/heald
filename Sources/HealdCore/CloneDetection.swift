import Foundation

/// Outcome of checking a stored `~/.heald/device.json` against the Mac it is running on.
public enum IdentityDecision: Equatable, Sendable {
    /// The record belongs to this Mac (or cannot be checked) — use it as is.
    case keep
    /// The record has no `hardwareUUID` — keep identity and token, only record the current UUID.
    case backfill
    /// The record was enrolled on another Mac (Migration Assistant, backup restore, sync) — re-enroll.
    case reenroll
}

/// Detects a `~/.heald` copied from another Mac and moves its per-device state aside (issue #18).
public enum CloneDetection {
    /// Decide whether a stored device record still belongs to this Mac.
    ///
    /// - `currentHardwareUUID == nil` (ioreg failed/timed out): `.keep`. Identity never rotates on a
    ///   failed probe; the check runs again on the next start.
    /// - Stored `hardwareUUID` present: `.reenroll` iff it differs (case/whitespace-insensitive).
    /// - Stored `hardwareUUID` nil: `.backfill` — keep `deviceId` and token, just record the UUID.
    ///   Such a record was enrolled while ioreg failed (or predates the field); there is no hardware
    ///   evidence that it came from another Mac, and rotating would churn the fleet token. Once
    ///   backfilled, a later copy of it to another Mac is detected by the rule above.
    public static func decide(
        storedHardwareUUID: String?,
        storedDeviceId: String,
        currentHardwareUUID: String?
    ) -> IdentityDecision {
        guard let current = normalized(currentHardwareUUID) else { return .keep }
        guard let stored = normalized(storedHardwareUUID) else { return .backfill }
        return stored == current ? .keep : .reenroll
    }

    /// Per-device files, relative to the heald root (`~/.heald`), that a cloned Mac must not reuse.
    /// History that is never re-sent (`data/activity.ndjson`, `data/metrics.db`, `data/cli-maintain.db`)
    /// stays in place: with the cursors moved, CloudPusher and SyslogSink restart at EOF.
    public static let perDeviceFiles: [String] = [
        "device.json",                  // identity + bearer token of the source Mac (copied, then replaced)
        "approvals.json",               // ApprovalStore: source Mac's pending approvals must not run here
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
        /// Paths (relative to the heald root) that were archived.
        public let moved: [String]
    }

    /// The identity file is archived by copy and only replaced by `commit` — it is never absent.
    public static let identityFile = "device.json"

    /// Archive every existing per-device file under `healdDir` into `healdDir/data/.cloned-…/` (never deletes).
    ///
    /// Order: create the archive dir atomically → move the per-device data files → copy `device.json`
    /// → `commit()` (the caller writes the new identity over `device.json`). If any step throws, every
    /// moved file is moved back and the error is rethrown, so `device.json` and the data stay in place.
    /// The archive directory remains as a trace even when there was nothing to move.
    public static func relocate(
        healdDir: URL,
        sourceDeviceId: String,
        now: Date = Date(),
        files: [String] = perDeviceFiles,
        fileManager fm: FileManager = .default,
        move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
        commit: () throws -> Void = {}
    ) throws -> Relocation {
        let archive = try makeArchiveDirectory(
            in: healdDir.appendingPathComponent("data"),
            name: archiveDirectoryName(sourceDeviceId: sourceDeviceId, now: now),
            fileManager: fm
        )
        var moved: [(rel: String, src: URL, dst: URL)] = []
        do {
            for rel in files where rel != identityFile {
                let src = healdDir.appendingPathComponent(rel)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = archive.appendingPathComponent(src.lastPathComponent)
                try move(src, dst)
                moved.append((rel, src, dst))
            }
            var archived = moved.map(\.rel)
            let id = healdDir.appendingPathComponent(identityFile)
            if files.contains(identityFile), fm.fileExists(atPath: id.path) {
                try fm.copyItem(at: id, to: archive.appendingPathComponent(identityFile))
                archived.insert(identityFile, at: 0)
            }
            try commit()
            return Relocation(archiveDirectory: archive, moved: archived)
        } catch {
            for m in moved.reversed() { try? fm.moveItem(at: m.dst, to: m.src) }
            throw error
        }
    }

    /// Create `name` (or `name-2`, `name-3`, …) without intermediates; EEXIST means "taken, try next",
    /// so two concurrent relocations can never share a directory.
    static func makeArchiveDirectory(in dataDir: URL, name: String, fileManager fm: FileManager) throws -> URL {
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        for n in 1...1000 {
            let url = dataDir.appendingPathComponent(n == 1 ? name : "\(name)-\(n)")
            if mkdir(url.path, 0o700) == 0 { return url }
            guard errno == EEXIST else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path,
                    NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)])
            }
        }
        throw CocoaError(.fileWriteFileExists, userInfo: [NSFilePathErrorKey: dataDir.appendingPathComponent(name).path])
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

/// Exclusive advisory lock (`flock`) on a file, serialising identity check + relocate + enroll between
/// the daemon and a manual `heald enroll`.
public enum IdentityLock {
    public static func withLock<T>(at url: URL, _ body: () throws -> T) rethrows -> T {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let fd = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return try body() } // cannot lock (read-only home?) — proceed unlocked
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 && errno == EINTR {}
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
