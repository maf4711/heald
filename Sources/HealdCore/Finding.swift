import Foundation

// Finding schema "heald.findings/v1" — one deduplicated device error, linked to the heal that addressed it.
// Encodes to JSON accepted by the dashboard's `validateFinding` (GOAL 4 heal-report.ts).

public enum FindingStatus: String, Codable, Sendable {
    case open, fixed, recurring
}

public enum FindingSeverity: String, Codable, Sendable, Comparable {
    case info, warning, error, critical

    private var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .error: 2
        case .critical: 3
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public enum FindingCategory: String, Codable, Sendable {
    case crash, panic, fault
    case launchdJob = "launchd_job"
}

public enum FindingSource: String, Codable, Sendable {
    case crashReport = "crash_report"
    case unifiedLog = "unified_log"
    case launchd
    case panicReport = "panic_report"
    case diagnosticReport = "diagnostic_report"
}

/// One classified occurrence from a log source, before dedupe.
public struct Observation: Sendable, Equatable {
    public var category: FindingCategory
    public var component: String
    /// Exception type, panic reason, diag event — empty when the component alone identifies it.
    public var signature: String
    public var source: FindingSource
    public var at: Date
    public var sample: String
    /// Source-specific severity (e.g. launchd exit code); nil → the fixed category table.
    public var severityOverride: FindingSeverity?

    public init(
        category: FindingCategory,
        component: String,
        signature: String,
        source: FindingSource,
        at: Date,
        sample: String,
        severityOverride: FindingSeverity? = nil
    ) {
        self.category = category
        self.component = component
        self.signature = signature
        self.source = source
        self.at = at
        self.sample = sample
        self.severityOverride = severityOverride
    }
}

public struct Finding: Codable, Sendable, Equatable {
    public static let schema = "heald.findings/v1"
    // Field caps shared with the dashboard validator.
    public static let maxFingerprint = 128
    public static let maxShort = 64
    public static let maxSample = 400
    public static let maxSources = 20
    public static let maxSourceChars = 256

    public var machineId: String
    public var fingerprint: String
    public var category: FindingCategory
    public var component: String
    public var severity: FindingSeverity
    public var count: Int
    public var firstSeen: Date
    public var lastSeen: Date
    public var status: FindingStatus
    public var recurrenceCount: Int
    public var sources: [String]
    /// Heal action that addressed this finding (`app_restart`, `dns_flush`, …); null until one ran.
    public var linkedAction: String?
    public var sample: String
    /// When the linked heal last succeeded; drives open → fixed after the quiet window.
    public var healedAt: Date?

    enum CodingKeys: String, CodingKey {
        case schema, machineId, fingerprint, category, component, severity, count
        case firstSeen, lastSeen, status, recurrenceCount, sources, linkedAction, sample, healedAt
    }

    public init(
        machineId: String,
        fingerprint: String,
        category: FindingCategory,
        component: String,
        severity: FindingSeverity,
        count: Int,
        firstSeen: Date,
        lastSeen: Date,
        status: FindingStatus,
        recurrenceCount: Int,
        sources: [String],
        linkedAction: String?,
        sample: String,
        healedAt: Date? = nil
    ) {
        self.machineId = machineId
        self.fingerprint = fingerprint
        self.category = category
        self.component = component
        self.severity = severity
        self.count = count
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.status = status
        self.recurrenceCount = recurrenceCount
        self.sources = sources
        self.linkedAction = linkedAction
        self.sample = sample
        self.healedAt = healedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machineId = try c.decodeIfPresent(String.self, forKey: .machineId) ?? ""
        fingerprint = try c.decode(String.self, forKey: .fingerprint)
        category = try c.decode(FindingCategory.self, forKey: .category)
        component = try c.decode(String.self, forKey: .component)
        severity = try c.decode(FindingSeverity.self, forKey: .severity)
        count = try c.decode(Int.self, forKey: .count)
        firstSeen = try c.decode(Date.self, forKey: .firstSeen)
        lastSeen = try c.decode(Date.self, forKey: .lastSeen)
        status = try c.decode(FindingStatus.self, forKey: .status)
        recurrenceCount = try c.decodeIfPresent(Int.self, forKey: .recurrenceCount) ?? 0
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        linkedAction = try c.decodeIfPresent(String.self, forKey: .linkedAction)
        sample = try c.decodeIfPresent(String.self, forKey: .sample) ?? ""
        healedAt = try c.decodeIfPresent(Date.self, forKey: .healedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schema, forKey: .schema)
        try c.encode(machineId, forKey: .machineId)
        try c.encode(fingerprint, forKey: .fingerprint)
        try c.encode(category, forKey: .category)
        try c.encode(component, forKey: .component)
        try c.encode(severity, forKey: .severity)
        try c.encode(count, forKey: .count)
        try c.encode(firstSeen, forKey: .firstSeen)
        try c.encode(lastSeen, forKey: .lastSeen)
        try c.encode(status, forKey: .status)
        try c.encode(recurrenceCount, forKey: .recurrenceCount)
        try c.encode(sources, forKey: .sources)
        try c.encode(linkedAction, forKey: .linkedAction) // explicit null: "no heal ran"
        try c.encode(sample, forKey: .sample)
        try c.encodeIfPresent(healedAt, forKey: .healedAt)
    }
}
