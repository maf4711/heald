import Foundation

/// Collapses noisy heal reports to at most one per `interval` per (action, outcome).
/// Noisy = consent blocks and advisor skip/defer for any action, and every outcome of the
/// always-on sub-healers that would otherwise report every tick. Suppressed occurrences are
/// counted into the `detail` of the next admitted report of the same key.
public struct HealReportLimiter: Sendable {
    public static let interval: TimeInterval = 3600
    public static let collapsedOutcomes: Set<HealOutcome> = [.blockedConsent, .advisorDeferred, .advisorSkipped]
    public static let collapsedActions: Set<String> = [DirectHeal.cpuStorm.rawValue, DirectHeal.batteryGuard.rawValue]

    private var last: [String: Date] = [:]
    private var suppressed: [String: Int] = [:]

    public init() {}

    public static func isCollapsed(_ r: HealReport) -> Bool {
        collapsedOutcomes.contains(r.outcome) || collapsedActions.contains(r.action)
    }

    private static func key(_ r: HealReport) -> String { "\(r.action)\u{0}\(r.outcome.rawValue)" }

    /// True when `r` should be written; may annotate `r.detail` with the suppressed count.
    public mutating func admit(_ r: inout HealReport) -> Bool {
        guard Self.isCollapsed(r) else { return true }
        let k = Self.key(r)
        if let t = last[k], abs(r.ts.timeIntervalSince(t)) < Self.interval {
            suppressed[k, default: 0] += 1
            return false
        }
        last[k] = r.ts
        if let n = suppressed.removeValue(forKey: k), n > 0 {
            let note = "\(n) similar reports suppressed in the last hour"
            r.detail = DiagnosisEngine.cap(r.detail.map { "\(note); \($0)" } ?? note, HealReport.maxDetail)
        }
        return true
    }

    /// Remember an already-written report (outbox tail at start-up) without admitting it.
    public mutating func seed(_ r: HealReport) {
        guard Self.isCollapsed(r) else { return }
        let k = Self.key(r)
        if let t = last[k], t >= r.ts { return }
        last[k] = r.ts
    }
}
