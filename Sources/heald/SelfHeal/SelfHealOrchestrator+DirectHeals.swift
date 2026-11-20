import Foundation
import HealdCore

extension SelfHealOrchestrator {
    /// Sub-healers with their own gates (not `fire`). Each reports one heal only when it acted.
    func runDirectHeals(policy: PolicyPack, tick: Int) async {
        // CPU storm (HUD dupes / leaked it2) every tick — not gated by consent=log.
        if policy.allowsPerformanceRemediation() {
            let start = ContinuousClock.now
            let killed = await perf.healCpuStorm(activityLog: activityLog)
            if !killed.isEmpty {
                let detail = killed.map { "\($0.1):\($0.0)" }.joined(separator: ",")
                await Self.recordDirectHeal(.cpuStorm, reason: "cpu storm (\(killed.count) process(es))",
                                            succeeded: true, since: start, detail: "killed \(detail)", policy: policy)
            }
        }

        // Battery + network every ~3 min
        if tick % 4 == 0 {
            var start = ContinuousClock.now
            if let alert = await batteryGuardian.evaluate(store: store, activityLog: activityLog, policy: policy) {
                await Self.recordDirectHeal(.batteryGuard, reason: "battery degraded", succeeded: true,
                                            since: start, detail: alert, policy: policy)
            }
            start = ContinuousClock.now
            if let net = await networkHeal.evaluate(store: store, activityLog: activityLog, policy: policy) {
                await Self.recordDirectHeal(.networkHeal, reason: net.detail, succeeded: net.succeeded,
                                            since: start, policy: policy)
            }
        }
        // Safe softwareupdate hourly-ish
        if tick % 80 == 0 {
            let start = ContinuousClock.now
            if let r = await safeUpdate.maybeRun(activityLog: activityLog, policy: policy) {
                await Self.recordDirectHeal(.safeUpdate, reason: "security/recommended updates listed",
                                            succeeded: r.succeeded, since: start, detail: r.summary, policy: policy)
            }
        }
    }

    /// Heal report for a heal outside `fire`: gate `.ran`, rules advisor, redacted like fire reports.
    static func recordDirectHeal(
        _ key: DirectHeal,
        reason: String,
        succeeded: Bool,
        since start: ContinuousClock.Instant,
        detail: String? = nil,
        policy: PolicyPack
    ) async {
        await HealReportOutbox.shared.append(DirectHeal.report(
            key,
            machineId: DeviceIdentity.machineId(),
            healdVersion: HealdApp.version,
            trigger: reason,
            consent: policy.healConsent,
            succeeded: succeeded,
            durationMs: ms(since: start),
            detail: detail,
            redact: PIIRedactor.redact
        ))
    }

    static func ms(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start) / .milliseconds(1))
    }
}

extension PolicyPack {
    /// Policy consent as carried by a heal report.
    var healConsent: HealConsent { HealConsent(rawValue: consent.rawValue) ?? .log }
}
