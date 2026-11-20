import Foundation
import Testing
@testable import HealdCore

private func fm(
    _ action: HealAction,
    _ rec: AdvisorRecommendation,
    confidence: Double = 0.9
) -> AdvisorVerdict {
    AdvisorVerdict(action: action, recommendation: rec, confidence: confidence,
                   rationale: "r", source: .appleFM, latencyMs: 5)
}

/// Reviewer fixes on top of GOAL 2: veto threshold, veto-proof actions, eligibility,
/// disposition, per-tick budget.
struct AdvisorPolicyTests {
    // MARK: fix 1 — low-confidence veto is ignored

    @Test func minVetoConfidenceIsPointSix() {
        #expect(AutohealAdvisor.minVetoConfidence == 0.6)
    }

    @Test func lowConfidenceSkipFallsBackToRules() {
        let out = AutohealAdvisor.gate(ruleAction: .diskCleanup, verdict: fm(.diskCleanup, .skip, confidence: 0.2))
        #expect(out.recommendation == .proceed)
        #expect(out.source == .rules)
    }

    @Test func lowConfidenceDeferFallsBackToRules() {
        let out = AutohealAdvisor.gate(ruleAction: .ramPurge, verdict: fm(.ramPurge, .defer, confidence: 0.59))
        #expect(out.recommendation == .proceed)
        #expect(out.source == .rules)
    }

    @Test func vetoAtThresholdIsHonoured() {
        let out = AutohealAdvisor.gate(ruleAction: .ramPurge, verdict: fm(.ramPurge, .skip, confidence: 0.6))
        #expect(out.recommendation == .skip)
        #expect(out.source == .appleFM)
    }

    @Test func lowConfidenceProceedStaysAdvisorProceed() {
        let out = AutohealAdvisor.gate(ruleAction: .ramPurge, verdict: fm(.ramPurge, .proceed, confidence: 0.1))
        #expect(out.recommendation == .proceed)
    }

    // MARK: fix 2 — security actions are veto-proof

    @Test func vetoProofActionsAreFirewallAndFileVault() {
        #expect(AutohealAdvisor.vetoProofActions == [.firewallOn, .filevaultWarn])
    }

    @Test(arguments: [HealAction.firewallOn, .filevaultWarn])
    func securityActionsIgnoreConfidentVeto(_ action: HealAction) {
        for rec in [AdvisorRecommendation.skip, .defer] {
            let out = AutohealAdvisor.gate(ruleAction: action, verdict: fm(action, rec, confidence: 1))
            #expect(out.recommendation == .proceed)
            #expect(out.source == .rules)
            #expect(out.action == action)
        }
    }

    // MARK: fix 3 — no FM consult for memory actions under critical pressure

    @Test func memoryCriticalOnlyAtKernelLevelFour() {
        #expect(AutohealAdvisor.isMemoryCritical(pressureLevel: 1) == false)
        #expect(AutohealAdvisor.isMemoryCritical(pressureLevel: 2) == false)
        #expect(AutohealAdvisor.isMemoryCritical(pressureLevel: 4) == true)
    }

    @Test(arguments: [HealAction.ramPurge, .perfAutoheal])
    func memoryActionsIneligibleWhenCritical(_ action: HealAction) {
        #expect(AutohealAdvisor.isEligible(action: action, memoryCritical: true) == false)
        #expect(AutohealAdvisor.isEligible(action: action, memoryCritical: false) == true)
    }

    @Test func otherActionsStayEligibleWhenMemoryCritical() {
        for action in HealAction.allCases where action != .ramPurge && action != .perfAutoheal {
            #expect(AutohealAdvisor.isEligible(action: action, memoryCritical: true) == true)
        }
    }

    // MARK: fix 5 — verdict → disposition is pure

    @Test func proceedMapsToRun() {
        #expect(AutohealAdvisor.disposition(fm(.diskCleanup, .proceed), cooldown: 1800) == .run)
        #expect(AutohealAdvisor.disposition(.rulesFallback(.diskCleanup), cooldown: 1800) == .run)
    }

    @Test func skipMapsToSkip() {
        #expect(AutohealAdvisor.disposition(fm(.diskCleanup, .skip), cooldown: 1800) == .skip)
    }

    @Test func deferMapsToDeferWithRetry() {
        if case .defer = AutohealAdvisor.disposition(fm(.diskCleanup, .defer), cooldown: 1800) {} else {
            Issue.record("defer verdict must map to .defer")
        }
    }

    /// `.run` only means "the advisor does not object"; it carries no consent decision.
    /// fire() evaluates consent after it (consent=log stays blocked there).
    @Test func runIsNotAConsentBypass() {
        let d = AutohealAdvisor.disposition(fm(.ramPurge, .proceed, confidence: 1), cooldown: 600)
        #expect(d == .run)
        #expect(d.consultsConsent == true)
        #expect(AdvisorDisposition.skip.consultsConsent == false)
        #expect(AdvisorDisposition.defer(retryAfter: 1).consultsConsent == false)
    }

    // MARK: fix 4 — defer re-arms after min(cooldown, 300 s); skip keeps full cooldown

    @Test func deferRetryIsCappedAtFiveMinutes() {
        #expect(AutohealAdvisor.maxDeferRetry == 300)
        #expect(AutohealAdvisor.disposition(fm(.diskCleanup, .defer), cooldown: 1800) == .defer(retryAfter: 300))
        #expect(AutohealAdvisor.disposition(fm(.perfAutoheal, .defer), cooldown: 120) == .defer(retryAfter: 120))
    }

    @Test func deferMarkIsBackdatedSoCooldownExpiresAfterRetry() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let mark = AutohealAdvisor.cooldownMark(now: now, cooldown: 1800, retryAfter: 300)
        #expect(mark == now.addingTimeInterval(-1500))
        // canFire(key, cooldown) is `elapsed >= cooldown` → re-armed exactly 300 s later
        #expect(now.addingTimeInterval(300).timeIntervalSince(mark) >= 1800)
        #expect(now.addingTimeInterval(299).timeIntervalSince(mark) < 1800)
    }

    @Test func skipMarkIsNowSoFullCooldownApplies() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(AutohealAdvisor.cooldownMark(now: now, cooldown: 1800, retryAfter: 1800) == now)
        #expect(AutohealAdvisor.cooldownMark(now: now, cooldown: 600, retryAfter: 900) == now)
    }
}
