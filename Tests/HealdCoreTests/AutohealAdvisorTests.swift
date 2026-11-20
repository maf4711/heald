import Foundation
import Testing
@testable import HealdCore

/// Thread-safe call counter for `ask` closures.
private actor CallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private func verdict(
    _ action: HealAction,
    _ recommendation: AdvisorRecommendation,
    confidence: Double = 0.9,
    rationale: String = "model says so"
) -> AdvisorVerdict {
    AdvisorVerdict(
        action: action,
        recommendation: recommendation,
        confidence: confidence,
        rationale: rationale,
        source: .appleFM,
        latencyMs: 12
    )
}

struct AutohealAdvisorTests {
    // MARK: catalog

    @Test func catalogRawValuesMatchCooldownKeys() {
        let keys = Set(HealAction.allCases.map(\.rawValue))
        #expect(keys == [
            "ram_purge", "disk_cleanup", "deep_trim", "firewall_on", "filevault_warn",
            "proactive_heal", "notify_thermal", "brew_light", "perf_autoheal",
            "app_restart", "dns_flush",
        ])
    }

    @Test func rulesFallbackIsProceedFromRulesWithZeroConfidence() {
        let v = AdvisorVerdict.rulesFallback(.diskCleanup)
        #expect(v.action == .diskCleanup)
        #expect(v.recommendation == .proceed)
        #expect(v.source == .rules)
        #expect(v.confidence == 0)
    }

    // MARK: gate (criterion 1)

    // (a)
    // (a) amended by review: firewall_on is veto-proof (see AdvisorPolicyTests), so the
    // honoured-skip case uses a non-security action.
    @Test func gateHonoursSkipForTriggeredAction() {
        let out = AutohealAdvisor.gate(ruleAction: .diskCleanup, verdict: verdict(.diskCleanup, .skip))
        #expect(out.recommendation == .skip)
        #expect(out.source == .appleFM)
        #expect(out.action == .diskCleanup)
    }

    @Test func gateHonoursDeferAndProceedForTriggeredAction() {
        #expect(AutohealAdvisor.gate(ruleAction: .ramPurge, verdict: verdict(.ramPurge, .defer)).recommendation == .defer)
        let proceed = AutohealAdvisor.gate(ruleAction: .ramPurge, verdict: verdict(.ramPurge, .proceed))
        #expect(proceed.recommendation == .proceed)
        #expect(proceed.source == .appleFM)
    }

    // (c)
    @Test func gateReplacesVerdictForDifferentActionWithRulesFallback() {
        let out = AutohealAdvisor.gate(ruleAction: .ramPurge, verdict: verdict(.deepTrim, .proceed))
        #expect(out.action == .ramPurge)
        #expect(out.recommendation == .proceed)
        #expect(out.source == .rules)
        #expect(out.confidence == 0)
    }

    @Test func gateCannotTurnDifferentActionSkipIntoSkipOfRuleAction() {
        let out = AutohealAdvisor.gate(ruleAction: .diskCleanup, verdict: verdict(.firewallOn, .skip))
        #expect(out.action == .diskCleanup)
        #expect(out.recommendation == .proceed)
        #expect(out.source == .rules)
    }

    // MARK: parse (criterion 2)

    // (b)
    @Test(arguments: ["rm -rf ~", "KILL", "", "   ", "sudo shutdown -h now", "{\"action\":\"rm -rf ~\",\"recommendation\":\"proceed\",\"confidence\":1,\"rationale\":\"x\"}"])
    func parseRejectsNonCatalogText(_ text: String) {
        let v = AutohealAdvisor.parse(text, ruleAction: .diskCleanup)
        #expect(v.source == .rules)
        #expect(v.recommendation == .proceed)
        #expect(v.confidence == 0)
        #expect(v.action == .diskCleanup)
    }

    @Test func parseRejectsUnknownRecommendation() {
        let json = #"{"action":"disk_cleanup","recommendation":"execute","confidence":0.9,"rationale":"x"}"#
        let v = AutohealAdvisor.parse(json, ruleAction: .diskCleanup)
        #expect(v.source == .rules)
    }

    @Test func parseRejectsOversizedText() {
        let pad = String(repeating: "a", count: 2100)
        let json = #"{"action":"disk_cleanup","recommendation":"skip","confidence":0.9,"rationale":"\#(pad)"}"#
        #expect(json.count > AutohealAdvisor.maxInputChars)
        let v = AutohealAdvisor.parse(json, ruleAction: .diskCleanup)
        #expect(v.source == .rules)
        #expect(v.recommendation == .proceed)
    }

    // (f)
    @Test func parseValidJSONRoundTripsAndTruncatesRationale() {
        let long = String(repeating: "r", count: 400)
        let json = #"{"action":"disk_cleanup","recommendation":"skip","confidence":0.82,"rationale":"\#(long)"}"#
        let v = AutohealAdvisor.parse(json, ruleAction: .diskCleanup)
        #expect(v.action == .diskCleanup)
        #expect(v.recommendation == .skip)
        #expect(v.confidence == 0.82)
        #expect(v.source == .appleFM)
        #expect(v.rationale.count == AutohealAdvisor.maxRationaleChars)
        #expect(AutohealAdvisor.maxRationaleChars == 280)
    }

    @Test func parseExampleFromGoal() {
        let json = #"{"action":"disk_cleanup","recommendation":"proceed","confidence":0.82,"rationale":"Root volume under 10 % free; caches and DerivedData are safe to clear."}"#
        let v = AutohealAdvisor.parse(json, ruleAction: .diskCleanup)
        #expect(v.recommendation == .proceed)
        #expect(v.source == .appleFM)
        #expect(v.rationale.hasPrefix("Root volume under 10 % free"))
    }

    @Test func parseClampsConfidence() {
        let json = #"{"action":"ram_purge","recommendation":"defer","confidence":7,"rationale":"x"}"#
        #expect(AutohealAdvisor.parse(json, ruleAction: .ramPurge).confidence == 1)
    }

    // MARK: consult (criterion 4)

    // (d)
    @Test func consultTimesOutWithRulesFallback() async {
        let clock = ContinuousClock()
        let start = clock.now
        let v = await AutohealAdvisor.consult(
            ruleAction: .diskCleanup,
            timeout: .seconds(5),
            available: true
        ) {
            try? await Task.sleep(for: .seconds(10))
            return #"{"action":"disk_cleanup","recommendation":"skip","confidence":1,"rationale":"late"}"#
        }
        let elapsed = clock.now - start
        #expect(elapsed < .seconds(6))
        #expect(v.source == .rules)
        #expect(v.recommendation == .proceed)
    }

    @Test func consultTimeoutHoldsEvenIfAskIgnoresCancellation() async {
        let clock = ContinuousClock()
        let start = clock.now
        let v = await AutohealAdvisor.consult(
            ruleAction: .ramPurge,
            timeout: .milliseconds(200),
            available: true
        ) {
            // Busy-wait style: ignores cancellation for ~1.5 s.
            let end = ContinuousClock.now + .milliseconds(1500)
            while ContinuousClock.now < end { await Task.yield() }
            return nil
        }
        #expect(clock.now - start < .seconds(1))
        #expect(v.source == .rules)
    }

    // (e)
    @Test func consultUnavailableNeverCallsAsk() async {
        let counter = CallCounter()
        let v = await AutohealAdvisor.consult(
            ruleAction: .firewallOn,
            timeout: .seconds(5),
            available: false
        ) {
            await counter.increment()
            return #"{"action":"firewall_on","recommendation":"skip","confidence":1,"rationale":"x"}"#
        }
        #expect(await counter.count == 0)
        #expect(v.source == .rules)
        #expect(v.recommendation == .proceed)
    }

    @Test func consultAppliesParseAndGate() async {
        let skip = await AutohealAdvisor.consult(ruleAction: .diskCleanup, timeout: .seconds(5), available: true) {
            #"{"action":"disk_cleanup","recommendation":"skip","confidence":0.7,"rationale":"plenty of purgeable space"}"#
        }
        #expect(skip.recommendation == .skip)
        #expect(skip.source == .appleFM)
        #expect(skip.latencyMs >= 0)

        let other = await AutohealAdvisor.consult(ruleAction: .ramPurge, timeout: .seconds(5), available: true) {
            #"{"action":"deep_trim","recommendation":"skip","confidence":0.7,"rationale":"x"}"#
        }
        #expect(other.source == .rules)
        #expect(other.recommendation == .proceed)

        let none = await AutohealAdvisor.consult(ruleAction: .ramPurge, timeout: .seconds(5), available: true) { nil }
        #expect(none.source == .rules)
    }

    @Test func verdictIsCodable() throws {
        let v = verdict(.perfAutoheal, .defer)
        let data = try JSONEncoder().encode(v)
        #expect(try JSONDecoder().decode(AdvisorVerdict.self, from: data) == v)
    }
}
