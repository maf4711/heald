import Foundation

/// Fixed catalog of self-heal actions the advisor may talk about.
/// Raw values are the SelfHealOrchestrator cooldown keys.
public enum HealAction: String, Codable, Sendable, CaseIterable {
    case ramPurge = "ram_purge"
    case diskCleanup = "disk_cleanup"
    case deepTrim = "deep_trim"
    case firewallOn = "firewall_on"
    case filevaultWarn = "filevault_warn"
    case proactiveHeal = "proactive_heal"
    case notifyThermal = "notify_thermal"
    case brewLight = "brew_light"
    case perfAutoheal = "perf_autoheal"
}

public enum AdvisorRecommendation: String, Codable, Sendable, CaseIterable {
    case proceed
    case `defer`
    case skip
}

public enum AdvisorSource: String, Codable, Sendable {
    case appleFM
    case rules
}

public struct AdvisorVerdict: Codable, Sendable, Equatable {
    public var action: HealAction
    public var recommendation: AdvisorRecommendation
    /// 0...1
    public var confidence: Double
    public var rationale: String
    public var source: AdvisorSource
    public var latencyMs: Int

    public init(
        action: HealAction,
        recommendation: AdvisorRecommendation,
        confidence: Double,
        rationale: String,
        source: AdvisorSource,
        latencyMs: Int
    ) {
        self.action = action
        self.recommendation = recommendation
        self.confidence = confidence
        self.rationale = rationale
        self.source = source
        self.latencyMs = latencyMs
    }

    /// The rules decide: proceed with the triggered action, confidence 0.
    public static func rulesFallback(
        _ action: HealAction,
        rationale: String = "rules fallback",
        latencyMs: Int = 0
    ) -> AdvisorVerdict {
        AdvisorVerdict(
            action: action,
            recommendation: .proceed,
            confidence: 0,
            rationale: rationale,
            source: .rules,
            latencyMs: latencyMs
        )
    }
}

extension AdvisorVerdict {
    /// Single-line JSON (sorted keys) for the `ai_advice` event's structured field.
    public var structuredJSON: String? {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? enc.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func truncated() -> AdvisorVerdict {
        var v = self
        v.rationale = String(v.rationale.prefix(AutohealAdvisor.maxRationaleChars))
        return v
    }
}

/// What fire() does with a gated verdict. Consent is evaluated only for `.run`, after this.
public enum AdvisorDisposition: Sendable, Equatable {
    case run
    case `defer`(retryAfter: TimeInterval)
    case skip

    /// Only `.run` continues to the consent gate; the advisor can never pass it.
    public var consultsConsent: Bool { self == .run }
}

/// Apple FM as autoheal **advisor**, never executor. Pure policy — no model, no shell.
/// The advisor may only downgrade a rule-triggered action (proceed → defer/skip);
/// it can never start an action or bypass consent.
public enum AutohealAdvisor: Sendable {
    public static let maxInputChars = 2000
    public static let maxRationaleChars = 280
    public static let defaultTimeout: Duration = .seconds(5)
    /// Rationale of the rules fallback produced by a consult timeout (trips `AdvisorBudget`).
    public static let timeoutRationale = "advisor timeout"
    /// A defer/skip below this confidence is ignored (rules decide).
    public static let minVetoConfidence = 0.6
    /// Security controls: the advisor is consulted and logged but can never downgrade them.
    public static let vetoProofActions: Set<HealAction> = [.firewallOn, .filevaultWarn]

    /// Actions that free memory: under critical pressure an on-device model load would make it worse.
    public static let memoryReliefActions: Set<HealAction> = [.ramPurge, .perfAutoheal]

    /// Kernel memory-pressure level 4 (1 normal, 2 warning, 4 critical).
    public static func isMemoryCritical(pressureLevel: Int) -> Bool {
        pressureLevel >= 4
    }

    /// Whether Apple FM may be consulted for `action` right now.
    public static func isEligible(action: HealAction, memoryCritical: Bool) -> Bool {
        !(memoryCritical && memoryReliefActions.contains(action))
    }

    /// Combine the rule decision with the advisor verdict.
    public static func gate(ruleAction: HealAction, verdict: AdvisorVerdict) -> AdvisorVerdict {
        guard verdict.action == ruleAction else {
            return .rulesFallback(
                ruleAction,
                rationale: "advisor named \(verdict.action.rawValue), ignored",
                latencyMs: verdict.latencyMs
            )
        }
        if verdict.recommendation != .proceed, vetoProofActions.contains(ruleAction) {
            return .rulesFallback(
                ruleAction,
                rationale: "veto-proof action, advisor \(verdict.recommendation.rawValue) ignored: \(verdict.rationale)",
                latencyMs: verdict.latencyMs
            ).truncated()
        }
        if verdict.recommendation != .proceed, verdict.confidence < minVetoConfidence {
            return .rulesFallback(
                ruleAction,
                rationale: "low-confidence \(verdict.recommendation.rawValue) ignored: \(verdict.rationale)",
                latencyMs: verdict.latencyMs
            ).truncated()
        }
        return verdict
    }

    /// A deferred action is reconsidered after at most this many seconds.
    public static let maxDeferRetry: TimeInterval = 300

    /// Timestamp to record as "last fired" so that a `cooldown` check re-arms after `retryAfter`.
    public static func cooldownMark(now: Date, cooldown: TimeInterval, retryAfter: TimeInterval) -> Date {
        now.addingTimeInterval(-(cooldown - min(max(retryAfter, 0), cooldown)))
    }

    /// Map a gated verdict to the orchestrator's next step for an action with `cooldown`.
    public static func disposition(_ verdict: AdvisorVerdict, cooldown: TimeInterval) -> AdvisorDisposition {
        switch verdict.recommendation {
        case .proceed: return .run
        case .defer: return .defer(retryAfter: min(cooldown, maxDeferRetry))
        case .skip: return .skip
        }
    }

    private struct Wire: Decodable {
        let action: String
        let recommendation: String
        let confidence: Double
        let rationale: String
    }

    /// Map model JSON to a verdict. Anything outside the catalog → rules fallback.
    public static func parse(_ text: String, ruleAction: HealAction) -> AdvisorVerdict {
        let fallback = AdvisorVerdict.rulesFallback(ruleAction, rationale: "advisor answer unparseable")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxInputChars,
              let wire = try? JSONDecoder().decode(Wire.self, from: Data(trimmed.utf8)),
              let action = HealAction(rawValue: wire.action),
              let recommendation = AdvisorRecommendation(rawValue: wire.recommendation.lowercased()),
              wire.confidence.isFinite
        else { return fallback }

        let rationale = wire.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        return AdvisorVerdict(
            action: action,
            recommendation: recommendation,
            confidence: min(max(wire.confidence, 0), 1),
            rationale: String(rationale.prefix(maxRationaleChars)),
            source: .appleFM,
            latencyMs: 0
        )
    }

    public static let memoryCriticalRationale = "memory critical — advisor skipped"
    public static let unavailableRationale = "Apple Intelligence unavailable"

    /// Ask the advisor with a hard deadline. Never calls `ask` when the model is unavailable
    /// or the action is ineligible under critical memory pressure.
    public static func consult(
        ruleAction: HealAction,
        timeout: Duration = defaultTimeout,
        available: Bool,
        memoryCritical: Bool = false,
        ask: @escaping @Sendable () async -> String?
    ) async -> AdvisorVerdict {
        guard isEligible(action: ruleAction, memoryCritical: memoryCritical) else {
            return .rulesFallback(ruleAction, rationale: memoryCriticalRationale)
        }
        guard available else {
            return .rulesFallback(ruleAction, rationale: unavailableRationale)
        }
        let clock = ContinuousClock()
        let start = clock.now
        let answer = await withDeadline(timeout, ask)
        let elapsed = clock.now - start
        let ms = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)

        switch answer {
        case .timedOut:
            return .rulesFallback(ruleAction, rationale: timeoutRationale, latencyMs: ms)
        case .value(nil):
            return .rulesFallback(ruleAction, rationale: "advisor gave no answer", latencyMs: ms)
        case .value(let text?):
            var verdict = gate(ruleAction: ruleAction, verdict: parse(text, ruleAction: ruleAction))
            verdict.latencyMs = ms
            return verdict
        }
    }

    public enum DeadlineResult<T: Sendable>: Sendable {
        case value(T)
        case timedOut
    }

    /// Run `work` but return no later than `timeout`, even if `work` ignores cancellation.
    public static func withDeadline<T: Sendable>(
        _ timeout: Duration,
        _ work: @escaping @Sendable () async -> T
    ) async -> DeadlineResult<T> {
        let slot = OneShot<DeadlineResult<T>>()
        let worker = Task { await slot.fulfil(.value(await work())) }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            await slot.fulfil(.timedOut)
        }
        let result = await slot.value()
        worker.cancel()
        timer.cancel()
        return result
    }
}

/// First `fulfil` wins; later ones are dropped.
private actor OneShot<T: Sendable> {
    private var result: T?
    private var waiters: [CheckedContinuation<T, Never>] = []

    func fulfil(_ value: T) {
        guard result == nil else { return }
        result = value
        let pending = waiters
        waiters = []
        for w in pending { w.resume(returning: value) }
    }

    func value() async -> T {
        if let result { return result }
        return await withCheckedContinuation { waiters.append($0) }
    }
}
