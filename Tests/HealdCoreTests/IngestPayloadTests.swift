import Foundation
import Testing
@testable import HealdCore

private func tmpDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("heald-ingest-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func report() -> HealReport {
    HealReport(
        machineId: "node-a", healdVersion: "3.5.0", action: "disk_cleanup", trigger: "t",
        consent: .auto, outcome: .executedOk, durationMs: 1, advisor: HealAdvisor(.rulesFallback(.diskCleanup))
    )
}

/// Reviewer fixes 1, 2, 5: ingest body, findings gate, poison-batch handling, timeouts.
struct IngestPayloadTests {
    @Test func findingsGateFiresOnRevisionChangeAndEveryThirtyPushes() {
        var gate = FindingsPushGate()
        #expect(gate.due(revision: 1)) // never sent
        gate.sent(revision: 1)
        #expect(!gate.due(revision: 1))
        #expect(gate.due(revision: 2)) // revision moved
        for _ in 0..<29 { gate.sent(revision: nil) }
        #expect(!gate.due(revision: 1))
        gate.sent(revision: nil)
        #expect(gate.due(revision: 1)) // 30 pushes without findings → periodic resend
        gate.sent(revision: 1)
        #expect(!gate.due(revision: 1))
    }

    @Test func bodyKeepsMetricsEventsAlwaysHasHealsFindingsOnlyWhenDue() throws {
        let base = try JSONSerialization.data(withJSONObject: [
            "metrics": ["machineId": "node-a"], "events": [["type": "x"]],
        ])
        let r = report()
        let finding = try DiagnosisEngine.encoder().encode([Finding(
            machineId: "node-a", fingerprint: "crash:Finder:X", category: .crash, component: "Finder",
            severity: .warning, count: 1, firstSeen: Date(), lastSeen: Date(), status: .open,
            recurrenceCount: 0, sources: ["crash_report"], linkedAction: nil, sample: "s"
        )])

        let with = try #require(try JSONSerialization.jsonObject(
            with: IngestPayload.body(base: base, heals: [r], findings: finding)) as? [String: Any])
        #expect((with["metrics"] as? [String: Any])?["machineId"] as? String == "node-a")
        #expect((with["events"] as? [Any])?.count == 1)
        let heals = try #require(with["heals"] as? [[String: Any]])
        #expect(heals.count == 1 && heals[0]["id"] as? String == r.id)
        #expect(validateHealReport(heals[0]) == nil)
        #expect((with["findings"] as? [Any])?.count == 1)

        let without = try #require(try JSONSerialization.jsonObject(
            with: IngestPayload.body(base: base, heals: [], findings: nil)) as? [String: Any])
        #expect((without["heals"] as? [Any])?.isEmpty == true)
        #expect(without["findings"] == nil)
    }

    @Test func poisonStatusIsA4xxOtherThanAuthAndRateLimit() {
        #expect(IngestPayload.isPoison(status: 400))
        #expect(IngestPayload.isPoison(status: 413))
        #expect(IngestPayload.isPoison(status: 422))
        #expect(!IngestPayload.isPoison(status: 401))
        #expect(!IngestPayload.isPoison(status: 429))
        #expect(!IngestPayload.isPoison(status: 200))
        #expect(!IngestPayload.isPoison(status: 500))
        #expect(!IngestPayload.isPoison(status: -1))
    }

    @Test func rejectedCountsAreReadFromTheIngestResponse() {
        let ok = Data(#"{"ok":true,"heals":{"accepted":3,"rejected":2},"findings":{"accepted":7,"rejected":1}}"#.utf8)
        #expect(IngestPayload.rejected(in: ok) == IngestPayload.Rejected(heals: 2, findings: 1))
        #expect(IngestPayload.rejected(in: Data("{\"ok\":true}".utf8)) == IngestPayload.Rejected(heals: 0, findings: 0))
        #expect(IngestPayload.rejected(in: Data("nope".utf8)) == nil)
    }

    @Test func requestTimesOutBeforeTheFlushDeadline() {
        #expect(IngestPayload.requestTimeout == 7)
        #expect(Duration.seconds(IngestPayload.requestTimeout) < HealReportOutbox.defaultSendTimeout)
    }

    @Test func skipAdvancesPastAPoisonBatchAndCountsIt() async throws {
        let outbox = HealReportOutbox(directory: tmpDir())
        for _ in 0..<130 { await outbox.append(report()) }
        let before = await outbox.committedOffset()
        #expect(await outbox.skip(limit: 500) == 100)
        #expect(await outbox.committedOffset() > before)
        #expect(await outbox.skippedCount == 100)
        #expect(await outbox.flush(limit: 100) { _ in true } == 30)
        #expect(await outbox.skip(limit: 100) == 0)
    }
}
