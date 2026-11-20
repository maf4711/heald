import Foundation
import Testing
@testable import HealdCore

/// Reviewer fix 6: circuit breaker after the first timeout, 10 s advisor budget per tick.
struct AdvisorBudgetTests {
    private func fmVerdict(latencyMs: Int) -> AdvisorVerdict {
        AdvisorVerdict(action: .diskCleanup, recommendation: .proceed, confidence: 0.9,
                       rationale: "ok", source: .appleFM, latencyMs: latencyMs)
    }

    @Test func freshBudgetIsTenSecondsAndAllowsFullTimeout() {
        let b = AdvisorBudget()
        #expect(AdvisorBudget.perTick == .seconds(10))
        #expect(b.nextTimeout() == .seconds(5))
    }

    @Test func timeoutTripsBreakerForRestOfTick() {
        var b = AdvisorBudget()
        b.record(.rulesFallback(.diskCleanup, rationale: AutohealAdvisor.timeoutRationale, latencyMs: 5000))
        #expect(b.tripped)
        #expect(b.nextTimeout() == nil)
    }

    @Test func nonTimeoutFallbackDoesNotTrip() {
        var b = AdvisorBudget()
        b.record(.rulesFallback(.diskCleanup, rationale: "advisor gave no answer", latencyMs: 30))
        #expect(!b.tripped)
        #expect(b.nextTimeout() == .seconds(5))
    }

    @Test func spentLatencyShrinksNextTimeout() {
        var b = AdvisorBudget()
        b.record(fmVerdict(latencyMs: 4000))
        b.record(fmVerdict(latencyMs: 3000))
        #expect(b.nextTimeout() == .seconds(3))
    }

    @Test func exhaustedBudgetAllowsNoMoreConsults() {
        var b = AdvisorBudget()
        b.record(fmVerdict(latencyMs: 4900))
        b.record(fmVerdict(latencyMs: 4900))
        b.record(fmVerdict(latencyMs: 400))
        #expect(b.nextTimeout() == nil)
        #expect(!b.tripped)
    }

    @Test func consultReportsTimeoutWithSharedRationale() async {
        let v = await AutohealAdvisor.consult(ruleAction: .ramPurge, timeout: .milliseconds(50), available: true) {
            try? await Task.sleep(for: .seconds(2))
            return nil
        }
        #expect(v.rationale == AutohealAdvisor.timeoutRationale)
        var b = AdvisorBudget()
        b.record(v)
        #expect(b.tripped)
    }
}
