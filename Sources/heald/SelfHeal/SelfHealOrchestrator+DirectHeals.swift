import Foundation
import HealdCore

extension SelfHealOrchestrator {
    /// Sub-healers with their own gates (not `fire`). Each reports one heal only when it acted.
    func runDirectHeals(policy: PolicyPack, tick: Int) async {
        let clock = ContinuousClock()

        // CPU storm (HUD dupes / leaked it2) every tick — not gated by consent=log.
        if policy.allowsPerformanceRemediation() {
            let start = clock.now
            let killed = await perf.healCpuStorm(activityLog: activityLog)
            if !killed.isEmpty {
                let detail = killed.map { "\($0.1):\($0.0)" }.joined(separator: ",")
                await Self.recordDirectHeal(.cpuStorm, reason: "cpu storm (\(killed.count) process(es))",
                                            succeeded: true, durationMs: Self.ms(clock.now - start),
                                            detail: "killed \(detail)", policy: policy)
            }
        }

        // Battery + network every ~3 min
        if tick % 4 == 0 {
            var start = clock.now
            if let alert = await batteryGuardian.evaluate(store: store, activityLog: activityLog, policy: policy) {
                await Self.recordDirectHeal(.batteryGuard, reason: "battery degraded", succeeded: true,
                                            durationMs: Self.ms(clock.now - start), detail: alert, policy: policy)
            }
            start = clock.now
            if let net = await networkHeal.evaluate(store: store, activityLog: activityLog, policy: policy) {
                await Self.recordDirectHeal(.networkHeal, reason: net.detail, succeeded: net.succeeded,
                                            durationMs: Self.ms(clock.now - start), policy: policy)
            }
        }
        // Safe softwareupdate hourly-ish
        if tick % 80 == 0 {
            let start = clock.now
            if let r = await safeUpdate.maybeRun(activityLog: activityLog, policy: policy) {
                await Self.recordDirectHeal(.safeUpdate, reason: "security/recommended updates listed",
                                            succeeded: r.succeeded, durationMs: Self.ms(clock.now - start),
                                            detail: r.summary, policy: policy)
            }
        }
    }

    /// Heal report for a heal outside `fire`: gate `.ran`, rules advisor, redacted like fire reports.
    static func recordDirectHeal(
        _ key: DirectHeal,
        reason: String,
        succeeded: Bool,
        durationMs: Int,
        detail: String? = nil,
        policy: PolicyPack
    ) async {
        await appendHealReport(DirectHeal.report(
            key,
            machineId: DeviceIdentity.machineId(),
            healdVersion: HealdApp.version,
            trigger: reason,
            consent: HealConsent(rawValue: policy.consent.rawValue) ?? .log,
            succeeded: succeeded,
            durationMs: durationMs,
            detail: detail,
            redact: PIIRedactor.redact
        ))
    }

    static func ms(_ d: Duration) -> Int { Int(d / .milliseconds(1)) }
}
