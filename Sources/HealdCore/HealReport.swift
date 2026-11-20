import Foundation

// Heal report schema "heald.heal_report/v1" — one record per self-heal decision.
// Encodes to JSON accepted by the dashboard's `validateHealReport` (GOAL 4 heal-report.ts).

public enum HealOutcome: String, Codable, Sendable, CaseIterable {
    case executedOk = "executed_ok"
    case executedFailed = "executed_failed"
    case blockedConsent = "blocked_consent"
    case approvedExecuted = "approved_executed"
    case advisorSkipped = "advisor_skipped"
    case advisorDeferred = "advisor_deferred"

    /// Report outcome for a `fire` gate decision; nil for cooldown (not a decision, never reported).
    public static func from(_ gate: GateOutcome, approved: Bool, succeeded: Bool) -> HealOutcome? {
        switch gate {
        case .cooldown: nil
        case .ran: succeeded ? (approved ? .approvedExecuted : .executedOk) : .executedFailed
        case .blockedAsk, .blockedLog: .blockedConsent
        case .advisorSkipped: .advisorSkipped
        case .advisorDeferred: .advisorDeferred
        }
    }
}

public enum HealConsent: String, Codable, Sendable {
    case auto, ask, log
}

/// The advisor verdict as carried by a heal report (`advisor` object).
public struct HealAdvisor: Codable, Sendable, Equatable {
    public var source: AdvisorSource
    public var recommendation: AdvisorRecommendation
    public var confidence: Double
    public var rationale: String
    public var latencyMs: Int

    public init(_ v: AdvisorVerdict) {
        source = v.source
        recommendation = v.recommendation
        confidence = v.confidence.isFinite ? v.confidence : 0
        rationale = v.rationale
        latencyMs = v.latencyMs
    }
}

public struct HealReport: Codable, Sendable, Equatable {
    public static let schema = "heald.heal_report/v1"
    // Field caps shared with the dashboard validator (UTF-16 units).
    public static let maxId = 128
    public static let maxShort = 64
    public static let maxText = 500
    public static let maxDetail = 4000

    public var id: String
    public var machineId: String
    public var ts: Date
    public var healdVersion: String
    public var action: String
    public var trigger: String
    public var consent: HealConsent
    public var outcome: HealOutcome
    public var durationMs: Int
    public var findingFingerprint: String?
    public var detail: String?
    public var advisor: HealAdvisor

    enum CodingKeys: String, CodingKey {
        case schema, id, machineId, ts, healdVersion, action, trigger, consent
        case outcome, durationMs, findingFingerprint, detail, advisor
    }

    /// Text fields are redacted (`redact`, then secrets + user paths) and capped to the validator limits.
    public init(
        id: String = UUID().uuidString.lowercased(),
        machineId: String,
        ts: Date = Date(),
        healdVersion: String,
        action: String,
        trigger: String,
        consent: HealConsent,
        outcome: HealOutcome,
        durationMs: Int,
        findingFingerprint: String? = nil,
        detail: String? = nil,
        advisor: HealAdvisor,
        redact: (String) -> String = { $0 }
    ) {
        func clean(_ s: String, _ n: Int) -> String {
            DiagnosisEngine.cap(DiagnosisEngine.redactPaths(SecretRedactor.redact(redact(s))), n)
        }
        self.id = DiagnosisEngine.cap(id, Self.maxId)
        self.machineId = DiagnosisEngine.cap(machineId, Self.maxId)
        self.ts = ts
        self.healdVersion = DiagnosisEngine.cap(healdVersion, Self.maxShort)
        self.action = DiagnosisEngine.cap(action, Self.maxShort)
        self.trigger = clean(trigger, Self.maxText)
        self.consent = consent
        self.outcome = outcome
        self.durationMs = max(0, durationMs)
        self.findingFingerprint = findingFingerprint.map { DiagnosisEngine.cap($0, Self.maxId) }
        self.detail = detail.map { clean($0, Self.maxDetail) }
        var adv = advisor
        adv.rationale = clean(adv.rationale, Self.maxText)
        self.advisor = adv
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(String.self, forKey: .schema) == Self.schema else {
            throw DecodingError.dataCorruptedError(forKey: .schema, in: c, debugDescription: "unknown schema")
        }
        id = try c.decode(String.self, forKey: .id)
        machineId = try c.decode(String.self, forKey: .machineId)
        ts = try c.decode(Date.self, forKey: .ts)
        healdVersion = try c.decode(String.self, forKey: .healdVersion)
        action = try c.decode(String.self, forKey: .action)
        trigger = try c.decode(String.self, forKey: .trigger)
        consent = try c.decode(HealConsent.self, forKey: .consent)
        outcome = try c.decode(HealOutcome.self, forKey: .outcome)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        findingFingerprint = try c.decodeIfPresent(String.self, forKey: .findingFingerprint)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        advisor = try c.decode(HealAdvisor.self, forKey: .advisor)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schema, forKey: .schema)
        try c.encode(id, forKey: .id)
        try c.encode(machineId, forKey: .machineId)
        try c.encode(ts, forKey: .ts)
        try c.encode(healdVersion, forKey: .healdVersion)
        try c.encode(action, forKey: .action)
        try c.encode(trigger, forKey: .trigger)
        try c.encode(consent, forKey: .consent)
        try c.encode(outcome, forKey: .outcome)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(findingFingerprint, forKey: .findingFingerprint) // explicit null: no linked finding
        try c.encodeIfPresent(detail, forKey: .detail)
        try c.encode(advisor, forKey: .advisor)
    }
}
