import Foundation

/// Per-tick advisor budget + circuit breaker. Pure value type, one instance per orchestrator tick.
/// - After the first advisor timeout the breaker trips: no more consults this tick (rules fallback).
/// - All consults in a tick share `perTick` (10 s) of wall time.
public struct AdvisorBudget: Sendable, Equatable {
    public static let perTick: Duration = .seconds(10)

    public private(set) var remaining: Duration
    public private(set) var tripped = false

    public init(total: Duration = perTick) {
        remaining = total
    }

    /// Timeout for the next consult, or nil when the breaker is open or the budget is spent.
    public func nextTimeout(cap: Duration = AutohealAdvisor.defaultTimeout) -> Duration? {
        guard !tripped, remaining > .zero else { return nil }
        return min(cap, remaining)
    }

    /// Account for a finished consult.
    public mutating func record(_ verdict: AdvisorVerdict) {
        remaining -= .milliseconds(max(verdict.latencyMs, 0))
        if verdict.source == .rules, verdict.rationale == AutohealAdvisor.timeoutRationale {
            tripped = true
        }
    }
}
