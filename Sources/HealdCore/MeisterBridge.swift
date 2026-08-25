import Foundation

/// Handshake with Meister / meisterSiri (`~/.meister/last.json`).
public struct MeisterLastRun: Codable, Sendable, Equatable {
    public var ts: String?
    public var score: Int?
    public var err: Int?
    public var twin: String?
    public var preferredTwin: String?

    enum CodingKeys: String, CodingKey {
        case ts, score, err, twin
        case preferredTwin = "preferred_twin"
    }

    public init(
        ts: String? = nil,
        score: Int? = nil,
        err: Int? = nil,
        twin: String? = nil,
        preferredTwin: String? = nil
    ) {
        self.ts = ts
        self.score = score
        self.err = err
        self.twin = twin
        self.preferredTwin = preferredTwin
    }
}

/// When to invoke the batch-maintain CLI. heald stays optional: no binary → skip.
public enum MeisterBridge: Sendable {
    public static func parseLast(_ data: Data) throws -> MeisterLastRun {
        try JSONDecoder().decode(MeisterLastRun.self, from: data)
    }

    public static func lastDate(_ run: MeisterLastRun) -> Date? {
        guard let ts = run.ts, !ts.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: ts) { return d }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: ts)
    }

    /// Once per local calendar day. Skip if a meister run is already in progress (lock).
    public static func shouldRun(
        last: MeisterLastRun?,
        now: Date,
        calendar: Calendar = .current,
        lockExists: Bool = false
    ) -> Bool {
        if lockExists { return false }
        guard let last, let date = lastDate(last) else { return true }
        return !calendar.isDate(date, inSameDayAs: now)
    }

    public static func resolveBinary(
        preferred: String?,
        exists: (String) -> Bool
    ) -> String? {
        let order: [String]
        if preferred == "meister" {
            order = ["meister", "meisterSiri"]
        } else {
            order = ["meisterSiri", "meister"]
        }
        for name in order {
            for root in ["/opt/homebrew/bin", "/usr/local/bin"] {
                let path = "\(root)/\(name)"
                if exists(path) { return path }
            }
        }
        return nil
    }
}
