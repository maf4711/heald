import Foundation

/// `~/.heald/data/findings.json` — the device's current error picture (schema heald.findings/v1).
public enum FindingsFile {
    struct Document: Codable {
        var schema: String
        var machineId: String
        var updatedAt: Date
        var unparsed: Int
        var findings: [Finding]
    }

    /// Atomic write: encode to a sibling temp file, then rename(2) over the target.
    /// A crash mid-write leaves the previous findings.json intact.
    public static func save(_ engine: DiagnosisEngine, to url: URL, now: Date = Date()) throws {
        let doc = Document(
            schema: Finding.schema,
            machineId: engine.machineId,
            updatedAt: now,
            unparsed: engine.unparsed,
            findings: engine.findings
        )
        let data = try DiagnosisEngine.encoder(pretty: true).encode(doc)
        let dir = url.deletingLastPathComponent()
        removeOrphanTempFiles(of: url)
        let tmp = dir.appendingPathComponent("\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        guard rename(tmp.path, url.path) == 0 else {
            let err = errno
            try? FileManager.default.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)])
        }
    }

    /// Missing or corrupt file → empty engine (never throws, never crashes the scan).
    /// A corrupt file is moved aside to `findings.json.corrupt-<epoch>` for inspection.
    public static func load(
        from url: URL,
        machineId: String,
        now: Date = Date(),
        quarantineCorrupt: Bool = true
    ) -> DiagnosisEngine {
        guard let data = try? Data(contentsOf: url) else { return DiagnosisEngine(machineId: machineId) }
        guard let doc = try? DiagnosisEngine.decoder().decode(Document.self, from: data),
              doc.schema == Finding.schema else {
            let aside = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).corrupt-\(Int(now.timeIntervalSince1970))")
            if quarantineCorrupt { try? FileManager.default.moveItem(at: url, to: aside) }
            return DiagnosisEngine(machineId: machineId)
        }
        return DiagnosisEngine(machineId: machineId, findings: doc.findings, unparsed: doc.unparsed)
    }

    /// Temp files left by a write that crashed before rename.
    private static func removeOrphanTempFiles(of url: URL) {
        let dir = url.deletingLastPathComponent()
        let prefix = "\(url.lastPathComponent).tmp-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in names where name.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }
}

extension DiagnosisEngine {
    // ISO8601DateFormatter is thread-safe; shared to avoid per-date allocation.
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()

    /// Dates as ISO 8601 with milliseconds (`2026-11-20T10:15:00.250Z`, 24 chars ≤ dashboard's 40).
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(isoFractional.string(from: date))
        }
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    /// Accepts ISO 8601 with or without fractional seconds.
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = isoFractional.date(from: s) ?? isoPlain.date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "bad date \(s)"))
            }
            return date
        }
        return d
    }
}

/// Seen-set for diagnostic reports. The first call primes (marks everything seen, returns nothing)
/// so a daemon start with 1000 old reports emits 0 findings.
public struct ReportSeenState: Sendable {
    public private(set) var seen: Set<String>
    public private(set) var primed: Bool

    public init(seen: Set<String> = [], primed: Bool = false) {
        self.seen = seen
        self.primed = primed
    }

    /// New paths (in input order), at most `limit`; only returned paths are marked seen.
    public mutating func fresh(_ paths: [String], limit: Int = .max) -> [String] {
        guard primed else {
            seen.formUnion(paths)
            primed = true
            return []
        }
        let out = Array(paths.filter { !seen.contains($0) }.prefix(limit))
        seen.formUnion(out)
        return out
    }

    /// Age-based trim: keep only paths still inside the scan window (mtime ≥ 24 h cutoff);
    /// anything older can never be reported again, so it no longer needs to be remembered.
    public mutating func retain(current: Set<String>) {
        seen.formIntersection(current)
    }
}
