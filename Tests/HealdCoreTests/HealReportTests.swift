import Foundation
import Synchronization
import Testing
@testable import HealdCore

/// Swift port of dashboard `validateHealReport` (GOAL 4 heal-report.ts) — the cross-GOAL contract.
/// Lengths are counted in UTF-16 units like JS `String.length`.
func validateHealReport(_ any: Any, now: Date = Date()) -> String? {
    guard let v = any as? [String: Any] else { return "not an object" }
    guard v["schema"] as? String == "heald.heal_report/v1" else { return "unknown schema" }
    func str(_ d: [String: Any], _ k: String, _ max: Int, required: Bool = false, nullable: Bool = false) -> String? {
        guard let raw = d[k] else { return required ? "missing \(k)" : nil }
        if raw is NSNull { return required ? "missing \(k)" : (nullable ? nil : "invalid \(k)") }
        guard let s = raw as? String else { return "invalid \(k)" }
        if required, s.trimmingCharacters(in: .whitespaces).isEmpty { return "missing \(k)" }
        return s.utf16.count > max ? "\(k) too long" : nil
    }
    func oneOf(_ d: [String: Any], _ k: String, _ allowed: [String], required: Bool = false, emptyIsMissing: Bool = false) -> String? {
        guard let raw = d[k], !(raw is NSNull), !(emptyIsMissing && raw as? String == "") else {
            return required ? "missing \(k)" : nil
        }
        return allowed.contains(raw as? String ?? "\u{0}") ? nil : "invalid \(k)"
    }
    func num(_ d: [String: Any], _ k: String) -> String? {
        guard let raw = d[k] else { return nil }
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return "invalid \(k)" }
        return n.doubleValue.isFinite ? nil : "invalid \(k)"
    }
    func iso(_ k: String) -> String? {
        guard let raw = v[k], !(raw is NSNull) else { return "missing \(k)" }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let s = raw as? String, s.utf16.count <= 40,
              let t = ISO8601DateFormatter().date(from: s) ?? frac.date(from: s) else { return "invalid \(k)" }
        return t > now.addingTimeInterval(24 * 3600) ? "\(k) in the future" : nil
    }
    func advisor() -> String? {
        guard let raw = v["advisor"], !(raw is NSNull) else { return "missing advisor" }
        guard let a = raw as? [String: Any] else { return "invalid advisor" }
        return [
            oneOf(a, "source", ["appleFM", "rules"], required: true),
            oneOf(a, "recommendation", ["proceed", "defer", "skip"], required: true),
            num(a, "confidence"), num(a, "latencyMs"),
            str(a, "rationale", 500),
        ].compactMap { $0 }.first
    }
    let checks: [String?] = [
        str(v, "id", 128, required: true),
        str(v, "machineId", 128, required: true),
        str(v, "action", 64, required: true),
        oneOf(v, "outcome", HealOutcome.allCases.map(\.rawValue), required: true, emptyIsMissing: true),
        iso("ts"),
        str(v, "healdVersion", 64),
        str(v, "trigger", 500),
        oneOf(v, "consent", ["auto", "ask", "log"]),
        num(v, "durationMs"),
        str(v, "findingFingerprint", 128, nullable: true),
        str(v, "detail", 4000),
        advisor(),
    ]
    return checks.compactMap { $0 }.first
}

/// GOAL 4 HEAL_KEYS + advisor (heal-report.ts).
private let healKeys: Set<String> = [
    "schema", "id", "machineId", "ts", "healdVersion", "action", "trigger", "consent",
    "outcome", "durationMs", "findingFingerprint", "detail", "advisor",
]

let healFixture = """
{"schema":"heald.heal_report/v1","id":"6f1c2b9e-0a3d-4c55-9a51-2f0f6f0d9b11","machineId":"node-a",\
"ts":"2026-11-20T10:15:00.250Z","healdVersion":"3.5.0","action":"disk_cleanup","trigger":"disk free 9%",\
"consent":"auto","outcome":"executed_ok","durationMs":4120,"findingFingerprint":null,"detail":"freed caches",\
"advisor":{"source":"appleFM","recommendation":"proceed","confidence":0.82,"rationale":"low disk","latencyMs":310}}
"""

private func tmpDir() -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("heald-heals-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private let verdict = AdvisorVerdict(
    action: .diskCleanup, recommendation: .proceed, confidence: 0.82,
    rationale: "low disk", source: .appleFM, latencyMs: 310
)

private func report(
    _ action: String = "disk_cleanup",
    outcome: HealOutcome = .executedOk,
    at ts: Date = Date(),
    detail: String? = nil
) -> HealReport {
    HealReport(
        machineId: "node-a", ts: ts, healdVersion: "3.5.0", action: action, trigger: "disk free 9%",
        consent: .auto, outcome: outcome, durationMs: 4120, findingFingerprint: nil, detail: detail,
        advisor: HealAdvisor(verdict)
    )
}

/// Collects what `send` received (Sendable, for the @Sendable closure).
private final class Sent: Sendable {
    let batches = Mutex<[[HealReport]]>([])
    func add(_ b: [HealReport]) { batches.withLock { $0.append(b) } }
    var counts: [Int] { batches.withLock { $0.map(\.count) } }
    var ids: [String] { batches.withLock { $0.flatMap { $0.map(\.id) } } }
}

private enum Boom: Error { case fail }

struct HealReportTests {
    // MARK: contract with the dashboard validator

    @Test func fixtureMatchesDashboardValidatorAndRoundTrips() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(healFixture.utf8))
        #expect(validateHealReport(obj) == nil)
        let r = try DiagnosisEngine.decoder().decode(HealReport.self, from: Data(healFixture.utf8))
        #expect(r.outcome == .executedOk)
        #expect(r.advisor.source == .appleFM)
        let re = try JSONSerialization.jsonObject(with: try DiagnosisEngine.encoder().encode(r))
        #expect(NSDictionary(dictionary: re as! [String: Any]) == NSDictionary(dictionary: obj as! [String: Any]))
    }

    // (a) key set + schema
    @Test func encodedReportHasGoal4KeySetAndSchema() throws {
        let data = try DiagnosisEngine.encoder().encode(report(detail: "x"))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(obj.keys) == healKeys)
        #expect(obj["schema"] as? String == "heald.heal_report/v1")
        #expect(obj["findingFingerprint"] is NSNull)
        #expect(validateHealReport(obj) == nil)
    }

    @Test func oversizedAndSecretTextIsCappedAndRedactedForEveryOutcome() throws {
        let huge = String(repeating: "🔥", count: 3000) // 6000 UTF-16 units
        for outcome in HealOutcome.allCases {
            let r = HealReport(
                machineId: String(repeating: "m", count: 300), healdVersion: "3.5.0",
                action: String(repeating: "a", count: 100),
                trigger: "Bearer abcdefghijklmnop /Users/marco/x " + huge,
                consent: .log, outcome: outcome, durationMs: 1,
                findingFingerprint: String(repeating: "f", count: 200),
                detail: huge, advisor: HealAdvisor(verdict)
            )
            let obj = try JSONSerialization.jsonObject(with: try DiagnosisEngine.encoder().encode(r))
            #expect(validateHealReport(obj) == nil, "outcome \(outcome)")
            #expect(!r.trigger.contains("abcdefghijklmnop"))
            #expect(!r.trigger.contains("marco"))
        }
    }

    @Test func gateOutcomesMapToHealOutcomes() {
        #expect(HealOutcome.from(.ran, approved: false, succeeded: true) == .executedOk)
        #expect(HealOutcome.from(.ran, approved: false, succeeded: false) == .executedFailed)
        #expect(HealOutcome.from(.ran, approved: true, succeeded: true) == .approvedExecuted)
        #expect(HealOutcome.from(.ran, approved: true, succeeded: false) == .executedFailed)
        #expect(HealOutcome.from(.blockedAsk, approved: false, succeeded: false) == .blockedConsent)
        #expect(HealOutcome.from(.blockedLog, approved: false, succeeded: false) == .blockedConsent)
        #expect(HealOutcome.from(.advisorSkipped, approved: false, succeeded: false) == .advisorSkipped)
        #expect(HealOutcome.from(.advisorDeferred, approved: false, succeeded: false) == .advisorDeferred)
        #expect(HealOutcome.from(.cooldown, approved: false, succeeded: false) == nil)
    }

    // (b) blocked_consent collapses to 1 per hour per action
    @Test func repeatedBlockedConsentCollapsesHourly() async throws {
        let outbox = HealReportOutbox(directory: tmpDir())
        let t0 = Date()
        var appended = 0
        for i in 0..<12 {
            let r = report("perf_autoheal", outcome: .blockedConsent, at: t0.addingTimeInterval(Double(i) * 300))
            if await outbox.append(r) { appended += 1 }
        }
        #expect(appended == 1)
        // Another action and the next hour are not collapsed.
        #expect(await outbox.append(report("ram_purge", outcome: .blockedConsent, at: t0)))
        #expect(await outbox.append(report("perf_autoheal", outcome: .blockedConsent, at: t0.addingTimeInterval(3600))))
        #expect(await outbox.append(report("perf_autoheal", outcome: .executedOk, at: t0)))
        #expect(await outbox.readBatch(since: 0, limit: 100).reports.count == 4)
    }

    // (c) send false / throw / timeout → cursor unchanged
    @Test func failedSendLeavesCursorUnchanged() async throws {
        let outbox = HealReportOutbox(directory: tmpDir(), sendTimeout: .milliseconds(200))
        for _ in 0..<3 { await outbox.append(report()) }
        let before = await outbox.committedOffset()
        #expect(await outbox.flush(limit: 100) { _ in false } == 0)
        #expect(await outbox.committedOffset() == before)
        #expect(await outbox.flush(limit: 100) { _ in throw Boom.fail } == 0)
        #expect(await outbox.committedOffset() == before)
        #expect(await outbox.flush(limit: 100) { _ in
            try? await Task.sleep(for: .seconds(5))
            return true
        } == 0)
        #expect(await outbox.committedOffset() == before)
        #expect(await outbox.flush(limit: 100) { _ in true } == 3)
        #expect(await outbox.committedOffset() > before)
    }

    @Test func defaultSendTimeoutIsEightSeconds() {
        #expect(HealReportOutbox.defaultSendTimeout == .seconds(8))
        #expect(HealReportOutbox.maxBatch == 100)
        #expect(HealReportOutbox.defaultMaxBytes == 10 * 1024 * 1024)
    }

    // (d) 150 queued → 100, then 50, oldest first; restart does not resend
    @Test func flushSendsAtMostHundredOldestFirstAndSurvivesRestart() async throws {
        let dir = tmpDir()
        let outbox = HealReportOutbox(directory: dir)
        var ids: [String] = []
        for _ in 0..<150 {
            let r = report()
            ids.append(r.id)
            await outbox.append(r)
        }
        let sent = Sent()
        #expect(await outbox.flush(limit: 500) { sent.add($0); return true } == 100)
        // Restart: a fresh outbox on the same directory resumes from the durable cursor.
        let restarted = HealReportOutbox(directory: dir)
        #expect(await restarted.flush(limit: 100) { sent.add($0); return true } == 50)
        #expect(await restarted.flush(limit: 100) { sent.add($0); return true } == 0)
        #expect(sent.counts == [100, 50, 0])
        #expect(sent.ids == ids)
    }

    @Test func cloudOffKeepsReportsAndLaterFlushesOldestFirst() async throws {
        let outbox = HealReportOutbox(directory: tmpDir())
        let first = report()
        await outbox.append(first)
        await outbox.append(report())
        // allowsCloud() false: CloudPusher never calls flush → nothing leaves, nothing is lost.
        #expect(await outbox.readBatch(since: await outbox.committedOffset(), limit: 100).reports.count == 2)
        let sent = Sent()
        #expect(await outbox.flush(limit: 1) { sent.add($0); return true } == 1)
        #expect(sent.ids == [first.id])
    }

    // (e) corrupt line skipped and counted
    @Test func corruptLineIsSkippedAndCounted() async throws {
        let dir = tmpDir()
        let outbox = HealReportOutbox(directory: dir)
        await outbox.append(report())
        let h = try FileHandle(forWritingTo: await outbox.fileURL)
        try h.seekToEnd()
        try h.write(contentsOf: Data("{\"schema\":\"heald.heal_report/v1\",\"id\":tru\n".utf8))
        try h.close()
        await outbox.append(report())
        let batch = await outbox.readBatch(since: 0, limit: 100)
        #expect(batch.reports.count == 2)
        #expect(batch.corrupt == 1)
        let sent = Sent()
        #expect(await outbox.flush(limit: 100) { sent.add($0); return true } == 2)
        #expect(await outbox.corruptCount == 1)
    }

    @Test func partialTrailingLineIsNotConsumed() async throws {
        let outbox = HealReportOutbox(directory: tmpDir())
        await outbox.append(report())
        let h = try FileHandle(forWritingTo: await outbox.fileURL)
        try h.seekToEnd()
        try h.write(contentsOf: Data("{\"schema\":\"heald".utf8))
        try h.close()
        let batch = await outbox.readBatch(since: 0, limit: 100)
        #expect(batch.reports.count == 1)
        #expect(batch.corrupt == 0)
        let size = try FileManager.default.attributesOfItem(atPath: await outbox.fileURL.path)[.size] as! UInt64
        #expect(batch.nextOffset < size)
    }

    // (f) two concurrent appends → two intact lines
    @Test func concurrentAppendsProduceIntactLines() async throws {
        let dir = tmpDir()
        let a = HealReportOutbox(directory: dir)
        let b = HealReportOutbox(directory: dir) // second writer on the same file (O_APPEND)
        async let x = a.append(report(detail: String(repeating: "x", count: 3000)))
        async let y = b.append(report(detail: String(repeating: "y", count: 3000)))
        _ = await (x, y)
        let text = try String(contentsOf: await a.fileURL, encoding: .utf8)
        let lines = text.split(separator: "\n")
        #expect(lines.count == 2)
        for line in lines {
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8))
            #expect(validateHealReport(obj) == nil)
        }
    }

    @Test func outboxIsCappedAndCursorFollowsRotation() async throws {
        let dir = tmpDir()
        let outbox = HealReportOutbox(directory: dir, maxBytes: 20_000)
        var ids: [String] = []
        for _ in 0..<5 {
            let r = report()
            ids.append(r.id)
            await outbox.append(r)
        }
        #expect(await outbox.flush(limit: 2) { _ in true } == 2) // first two delivered
        for _ in 0..<60 {
            let r = report(detail: String(repeating: "d", count: 300))
            ids.append(r.id)
            await outbox.append(r)
        }
        let size = try FileManager.default.attributesOfItem(atPath: await outbox.fileURL.path)[.size] as! Int
        #expect(size <= 20_000)
        let sent = Sent()
        while await outbox.flush(limit: 100, send: { sent.add($0); return true }) > 0 {}
        // Oldest lines were rotated away; what remains is a contiguous newest tail, never resent.
        let got = sent.ids
        #expect(!got.isEmpty)
        #expect(got == Array(ids.suffix(got.count)))
        #expect(!got.contains(ids[0]) && !got.contains(ids[1]))
    }
}
