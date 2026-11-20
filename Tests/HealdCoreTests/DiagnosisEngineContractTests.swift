import Foundation
import Testing
@testable import HealdCore

/// Swift port of dashboard `validateFinding` (GOAL 4 heal-report.ts) — the cross-GOAL contract.
private func validateFinding(_ any: Any) -> String? {
    guard let v = any as? [String: Any] else { return "not an object" }
    guard v["schema"] as? String == "heald.findings/v1" else { return "unknown schema" }
    func str(_ k: String, _ max: Int, required: Bool = false, nullable: Bool = false) -> String? {
        guard let raw = v[k] else { return required ? "missing \(k)" : nil }
        if raw is NSNull { return required ? "missing \(k)" : (nullable ? nil : "invalid \(k)") }
        guard let s = raw as? String else { return "invalid \(k)" }
        if required, s.trimmingCharacters(in: .whitespaces).isEmpty { return "missing \(k)" }
        return s.count > max ? "\(k) too long" : nil
    }
    func oneOf(_ k: String, _ allowed: [String], required: Bool = false) -> String? {
        guard let raw = v[k], !(raw is NSNull) else { return required ? "missing \(k)" : nil }
        return allowed.contains(raw as? String ?? "\u{0}") ? nil : "invalid \(k)"
    }
    func num(_ k: String) -> String? {
        guard let raw = v[k] else { return nil }
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return "invalid \(k)" }
        return n.doubleValue.isFinite ? nil : "invalid \(k)"
    }
    func iso(_ k: String, required: Bool = false) -> String? {
        guard let raw = v[k], !(raw is NSNull) else { return required ? "missing \(k)" : nil }
        guard let s = raw as? String, s.count <= 40, ISO8601DateFormatter().date(from: s) != nil else {
            return "invalid \(k)"
        }
        return nil
    }
    func sources() -> String? {
        guard let raw = v["sources"] else { return nil }
        guard let arr = raw as? [Any], arr.count <= 20 else { return "invalid sources" }
        return arr.allSatisfy { ($0 as? String).map { $0.count <= 256 } ?? false } ? nil : "invalid sources"
    }
    let checks: [String?] = [
        str("fingerprint", 128, required: true),
        str("machineId", 128, required: true),
        oneOf("status", ["open", "fixed", "recurring"], required: true),
        oneOf("severity", ["info", "warning", "error", "critical"], required: true),
        str("category", 64), str("component", 64),
        str("linkedAction", 64, nullable: true),
        num("count"), num("recurrenceCount"),
        iso("firstSeen"), iso("lastSeen"),
        str("sample", 400), sources(),
    ]
    return checks.compactMap { $0 }.first
}

private let fixture = """
{"schema":"heald.findings/v1","machineId":"node-a","fingerprint":"crash:Finder:EXC_BAD_ACCESS",\
"category":"crash","component":"Finder","severity":"warning","count":12,"status":"fixed",\
"recurrenceCount":0,"linkedAction":"app_restart","firstSeen":"2026-11-20T10:15:00Z",\
"lastSeen":"2026-11-20T12:05:00Z","sources":["crash_report"],"sample":"Finder crashed: EXC_BAD_ACCESS"}
"""

private func tmpDir() -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("heald-findings-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

extension DiagnosisEngineTests {
    // MARK: dashboard contract

    @Test func fixtureMatchesDashboardValidatorAndDecodes() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(fixture.utf8))
        #expect(validateFinding(obj) == nil)
        let f = try DiagnosisEngine.decoder().decode(Finding.self, from: Data(fixture.utf8))
        #expect(f.status == .fixed)
        #expect(f.linkedAction == "app_restart")
        #expect(f.count == 12)
        let re = try JSONSerialization.jsonObject(with: try DiagnosisEngine.encoder().encode(f))
        #expect(validateFinding(re) == nil)
        #expect(NSDictionary(dictionary: re as! [String: Any]) == NSDictionary(dictionary: obj as! [String: Any]))
    }

    @Test func encodedFindingsPassValidatorEvenWithOversizedInput() throws {
        var engine = DiagnosisEngine(machineId: "node-a")
        let long = String(repeating: "x", count: 300)
        engine.ingest(Observation(
            category: .crash, component: long, signature: long,
            source: .crashReport, at: Date(), sample: String(repeating: "s", count: 5000)
        ))
        engine.ingest(Observation(
            category: .fault, component: "mds", signature: "", source: .unifiedLog, at: Date(), sample: "x"
        ))
        let data = try DiagnosisEngine.encoder().encode(engine.findings)
        let arr = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(arr.count == 2)
        for item in arr { #expect(validateFinding(item) == nil) }
        // linkedAction is emitted as explicit null when no heal ran.
        #expect(arr.allSatisfy { $0["linkedAction"] is NSNull })
    }

    // MARK: criterion 5 — atomic findings.json

    @Test func findingsFileRoundTripsAndSurvivesCrashMidWrite() throws {
        let dir = tmpDir()
        let url = dir.appendingPathComponent("findings.json")
        var engine = DiagnosisEngine(machineId: "node-a")
        engine.ingest(Observation(
            category: .crash, component: "Finder", signature: "EXC_CRASH",
            source: .crashReport, at: Date(timeIntervalSince1970: 1_795_000_000), sample: "s"
        ))
        engine.noteUnparsed()
        try FindingsFile.save(engine, to: url)

        // Simulate a crash mid-write: a half-written temp sibling is left behind.
        try Data(#"{"schema":"heald.findings/v1","findings":[{"fing"#.utf8)
            .write(to: dir.appendingPathComponent("findings.json.tmp-crashed"))
        let loaded = FindingsFile.load(from: url, machineId: "node-a")
        #expect(loaded.findings == engine.findings)
        #expect(loaded.unparsed == 1)
        let doc = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(doc["schema"] as? String == "heald.findings/v1")
        #expect(doc["unparsed"] as? Int == 1)
        for item in try #require(doc["findings"] as? [[String: Any]]) { #expect(validateFinding(item) == nil) }

        // A second save replaces the file atomically and leaves no temp file of its own.
        engine.noteUnparsed()
        try FindingsFile.save(engine, to: url)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("findings.json.tmp-") && $0 != "findings.json.tmp-crashed" }
        #expect(leftovers.isEmpty)
        #expect(FindingsFile.load(from: url, machineId: "node-a").unparsed == 2)
    }

    @Test func corruptFindingsFileLoadsEmptyInsteadOfCrashing() throws {
        let url = tmpDir().appendingPathComponent("findings.json")
        try Data([0xff, 0x00, 0x7b, 0x22]).write(to: url)
        let engine = FindingsFile.load(from: url, machineId: "node-a")
        #expect(engine.findings.isEmpty)
        #expect(engine.machineId == "node-a")
    }

    // MARK: criterion 3 — remediation planning (execution goes through SelfHealOrchestrator.fire)

    @Test func scannerRemediationsMapToHealActions() {
        #expect(HealAction(rawValue: "app_restart") == .appRestart)
        #expect(HealAction(rawValue: "dns_flush") == .dnsFlush)
        let finder = Observation(category: .crash, component: "Finder", signature: "EXC_CRASH",
                                 source: .crashReport, at: Date(), sample: "")
        let xcode = Observation(category: .crash, component: "Xcode", signature: "EXC_CRASH",
                                source: .crashReport, at: Date(), sample: "")
        #expect(DiagnosisEngine.remediation(for: finder, isRunning: false) == .appRestart)
        #expect(DiagnosisEngine.remediation(for: finder, isRunning: true) == nil)
        #expect(DiagnosisEngine.remediation(for: xcode, isRunning: false) == nil)
        #expect(DiagnosisEngine.dnsFlushNeeded(faultCounts: ["mDNSResponder": 3]))
        #expect(!DiagnosisEngine.dnsFlushNeeded(faultCounts: ["mDNSResponder": 2, "cloudd": 9]))
    }
}
