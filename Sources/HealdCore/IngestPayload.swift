import Foundation

/// POST /api/ingest body assembly and response handling (shared by CloudPusher, unit-tested here).
public enum IngestPayload {
    /// URLSession gives up before `HealReportOutbox.defaultSendTimeout` (8 s) cancels the send.
    public static let requestTimeout: TimeInterval = 7

    /// The metrics/events payload plus `heals` (always, possibly empty) and `findings` (only when due).
    public static func body(base: Data, heals: [HealReport], findings: Data?) throws -> Data {
        guard var dict = try JSONSerialization.jsonObject(with: base) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        dict["heals"] = try JSONSerialization.jsonObject(with: DiagnosisEngine.encoder().encode(heals))
        if let findings { dict["findings"] = try JSONSerialization.jsonObject(with: findings) }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    /// A 4xx that will repeat for the same body (not auth, not rate limit): the batch is poison.
    public static func isPoison(status: Int) -> Bool {
        (400..<500).contains(status) && status != 401 && status != 429
    }

    public struct Rejected: Sendable, Equatable {
        public var heals: Int
        public var findings: Int
        public init(heals: Int, findings: Int) {
            self.heals = heals
            self.findings = findings
        }
    }

    /// `heals.rejected` / `findings.rejected` from a 200 ingest response; nil when not JSON.
    public static func rejected(in response: Data) -> Rejected? {
        guard let obj = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else { return nil }
        func count(_ k: String) -> Int { ((obj[k] as? [String: Any])?["rejected"] as? Int) ?? 0 }
        return Rejected(heals: count("heals"), findings: count("findings"))
    }
}

/// Findings are sent when the engine revision moved, and re-sent every `resendEvery` pushes
/// so a dashboard cold start re-learns the current picture.
public struct FindingsPushGate: Sendable {
    public static let resendEvery = 30 // × 10 s push interval = 5 min
    private var lastRevision: Int?
    private var pushesSince = 0

    public init() {}

    public func due(revision: Int) -> Bool {
        lastRevision != revision || pushesSince >= Self.resendEvery
    }

    /// After a successful push: `revision` of the findings it carried, nil when it carried none.
    public mutating func sent(revision: Int?) {
        if let revision {
            lastRevision = revision
            pushesSince = 0
        } else {
            pushesSince += 1
        }
    }
}
