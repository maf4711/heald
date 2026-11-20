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
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).tmp-\(UUID().uuidString)")
        try data.write(to: tmp)
        guard rename(tmp.path, url.path) == 0 else {
            let err = errno
            try? FileManager.default.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: err) ?? .EIO)])
        }
    }

    /// Missing or corrupt file → empty engine (never throws, never crashes the scan).
    public static func load(from url: URL, machineId: String) -> DiagnosisEngine {
        guard let data = try? Data(contentsOf: url),
              let doc = try? DiagnosisEngine.decoder().decode(Document.self, from: data),
              doc.schema == Finding.schema else {
            return DiagnosisEngine(machineId: machineId)
        }
        return DiagnosisEngine(machineId: machineId, findings: doc.findings, unparsed: doc.unparsed)
    }
}

extension DiagnosisEngine {
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = plain.date(from: s) ?? frac.date(from: s) else {
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

    /// Bound the persisted set (same limits as the original scanner state).
    public mutating func trim(keep: Int = 1000, above: Int = 2000) {
        if seen.count > above { seen = Set(seen.prefix(keep)) }
    }
}
