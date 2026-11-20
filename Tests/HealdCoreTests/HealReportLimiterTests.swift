import Foundation
import Testing
@testable import HealdCore

private func tmpDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("heald-limiter-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func report(_ action: String, _ outcome: HealOutcome, at ts: Date, detail: String? = nil) -> HealReport {
    HealReport(
        machineId: "node-a", ts: ts, healdVersion: "3.5.0", action: action, trigger: "t",
        consent: .auto, outcome: outcome, durationMs: 1, detail: detail,
        advisor: HealAdvisor(.rulesFallback(.perfAutoheal))
    )
}

/// Reviewer fix 3 + 7: collapse limiter keyed on (action, outcome), seeded from the outbox tail.
struct HealReportLimiterTests {
    @Test func noisyOutcomesCollapseHourlyPerActionAndOutcome() {
        var limiter = HealReportLimiter()
        let t0 = Date()
        for outcome in [HealOutcome.blockedConsent, .advisorDeferred, .advisorSkipped] {
            var admitted = 0
            for i in 0..<12 {
                var r = report("perf_autoheal", outcome, at: t0.addingTimeInterval(Double(i) * 300))
                if limiter.admit(&r) { admitted += 1 }
            }
            #expect(admitted == 1, "\(outcome)")
        }
        // Same action, ordinary outcome: never collapsed.
        for i in 0..<3 {
            var r = report("perf_autoheal", .executedOk, at: t0.addingTimeInterval(Double(i)))
            do { let ok = limiter.admit(&r); #expect(ok) }
        }
        // Next hour is admitted again.
        var later = report("perf_autoheal", .advisorDeferred, at: t0.addingTimeInterval(3600))
        do { let ok = limiter.admit(&later); #expect(ok) }
    }

    @Test func cpuStormAndBatteryGuardCollapseForEveryOutcome() {
        var limiter = HealReportLimiter()
        let t0 = Date()
        for action in ["cpu_storm", "battery_guard"] {
            var first = report(action, .executedOk, at: t0)
            do { let ok = limiter.admit(&first); #expect(ok) }
            var second = report(action, .executedOk, at: t0.addingTimeInterval(60))
            do { let ok = limiter.admit(&second); #expect(!ok) }
        }
        var disk = report("disk_cleanup", .executedOk, at: t0)
        var disk2 = report("disk_cleanup", .executedOk, at: t0.addingTimeInterval(60))
        let a = limiter.admit(&disk)
        let b = limiter.admit(&disk2)
        #expect(a && b)
    }

    @Test func suppressedCountIsCarriedIntoTheNextReport() {
        var limiter = HealReportLimiter()
        let t0 = Date()
        var first = report("cpu_storm", .executedOk, at: t0)
        do { let ok = limiter.admit(&first); #expect(ok) }
        for i in 1...4 {
            var r = report("cpu_storm", .executedOk, at: t0.addingTimeInterval(Double(i) * 600))
            do { let ok = limiter.admit(&r); #expect(!ok) }
        }
        var next = report("cpu_storm", .executedOk, at: t0.addingTimeInterval(3600), detail: "killed HUD:123")
        do { let ok = limiter.admit(&next); #expect(ok) }
        #expect(next.detail?.hasPrefix("4 similar reports suppressed") == true)
        #expect(next.detail?.hasSuffix("killed HUD:123") == true)
        var after = report("cpu_storm", .executedOk, at: t0.addingTimeInterval(7200))
        do { let ok = limiter.admit(&after); #expect(ok) }
        #expect(after.detail == nil)
    }

    @Test func restartSeedsLimiterFromOutboxTail() async throws {
        let dir = tmpDir()
        let t0 = Date()
        let first = HealReportOutbox(directory: dir)
        #expect(await first.append(report("perf_autoheal", .blockedConsent, at: t0)))
        #expect(await first.append(report("cpu_storm", .executedOk, at: t0)))
        // Crash loop: a fresh daemon on the same directory must not re-report within the hour.
        let restarted = HealReportOutbox(directory: dir)
        #expect(!(await restarted.append(report("perf_autoheal", .blockedConsent, at: t0.addingTimeInterval(45)))))
        #expect(!(await restarted.append(report("cpu_storm", .executedOk, at: t0.addingTimeInterval(45)))))
        #expect(await restarted.append(report("perf_autoheal", .executedOk, at: t0.addingTimeInterval(45))))
    }

    @Test func appendRepairsAMissingTrailingNewline() async throws {
        let outbox = HealReportOutbox(directory: tmpDir())
        try Data("{\"schema\":\"heald".utf8).write(to: await outbox.fileURL) // crashed half-line
        #expect(await outbox.append(report("disk_cleanup", .executedOk, at: Date())))
        let batch = await outbox.readBatch(since: 0, limit: 100)
        #expect(batch.reports.count == 1)
        #expect(batch.corrupt == 1)
    }

    @Test func capIsPublicAndCountsUTF16() {
        #expect(DiagnosisEngine.cap(String(repeating: "🔥", count: 10), 5).utf16.count == 4)
    }
}

/// Reviewer fix 4: heals outside `fire` report through the same path with a rules advisor.
struct DirectHealReportTests {
    @Test func directHealKeysPassTheDashboardValidator() throws {
        #expect(DirectHeal.allCases.map(\.rawValue) == ["cpu_storm", "battery_guard", "network_heal", "safe_update"])
        for action in DirectHeal.allCases {
            for ok in [true, false] {
                let r = DirectHeal.report(
                    action, machineId: "node-a", healdVersion: "3.5.0", trigger: "t", consent: .log,
                    succeeded: ok, durationMs: 12, detail: "killed HUD:123"
                )
                #expect(r.outcome == (ok ? .executedOk : .executedFailed))
                #expect(r.advisor.source == .rules && r.advisor.recommendation == .proceed && r.advisor.confidence == 0)
                let obj = try JSONSerialization.jsonObject(with: DiagnosisEngine.encoder().encode(r))
                #expect(validateHealReport(obj) == nil)
            }
        }
    }

    @Test func cpuStormSuccessCollapsesButNetworkHealDoesNot() {
        var limiter = HealReportLimiter()
        func make(_ a: DirectHeal) -> HealReport {
            DirectHeal.report(a, machineId: "m", healdVersion: "v", trigger: "t", consent: .auto, succeeded: true, durationMs: 1)
        }
        var a = make(.cpuStorm), b = make(.cpuStorm), c = make(.networkHeal), d = make(.networkHeal)
        let r = (limiter.admit(&a), limiter.admit(&b), limiter.admit(&c), limiter.admit(&d))
        #expect(r == (true, false, true, true))
    }
}
