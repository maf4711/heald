import Foundation
import Testing
@testable import HealdCore

private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

private func obs(
    _ category: FindingCategory, _ component: String, _ signature: String = "",
    source: FindingSource, at: Date = t0, sample: String = "s"
) -> Observation {
    Observation(category: category, component: component, signature: signature, source: source, at: at, sample: sample)
}

/// Reviewer findings B2, F3–F8, N2–N8 on goal/device-findings.
extension DiagnosisEngineTests {
    // MARK: B2 — panic strings with escaped quotes

    @Test func panicWithEscapedQuotedMessageParses() throws {
        let sample = #"panic(cpu 6 caller 0xfffffe0012345678): \"apciec[pcic2-bridge]::handleInterrupt: request completion timeout\" @AppleT8103PCIeCPort.cpp:1301"#
        let json = #"{"bug_type":"210"}"# + "\n" + #"{"panicString":""# + sample + #"\n"}"#
        let o = try #require(DiagnosisEngine.classifyReport(filename: "panic-full-2026-11-20-101500.panic", contents: json, at: t0))
        #expect(DiagnosisEngine.fingerprint(for: o)
            == "panic:kernel:apciec[pcic#-bridge]::handleInterrupt: request completion timeout")
        let raw = try #require(DiagnosisEngine.classifyReport(filename: "Kernel-2026-11-20.panic", contents: sample, at: t0))
        #expect(raw.signature == o.signature)
    }

    @Test func panicFileWithoutParseableStringIsUnknownNotUnparsed() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingestReport(filename: "kernel-2026-11-20.panic", contents: "\u{1}\u{2} binary junk", at: t0)
        #expect(engine.unparsed == 0)
        #expect(engine.findings.first?.fingerprint == "panic:kernel:unknown")
        #expect(engine.findings.first?.severity == .critical)
    }

    // MARK: F3 — fault merges only into a live, recent crash finding

    @Test func faultMergesOnlyIntoRecentUnfixedCrash() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let crashFP = engine.ingest(obs(.crash, "WindowServer", "EXC_CRASH", source: .crashReport))
        #expect(engine.ingest(obs(.fault, "WindowServer", source: .unifiedLog, at: t0.addingTimeInterval(600))) == crashFP)
        // > 10 min after the crash's lastSeen → own finding
        #expect(engine.ingest(obs(.fault, "WindowServer", source: .unifiedLog, at: t0.addingTimeInterval(1300)))
            == "fault:WindowServer")
    }

    @Test func faultDoesNotMergeIntoFixedCrash() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let crashFP = engine.ingest(obs(.crash, "Dock", "EXC_CRASH", source: .crashReport))
        engine.recordHeal(fingerprint: crashFP, action: "app_restart", succeeded: true, at: t0)
        engine.refresh(now: t0.addingTimeInterval(1800))
        #expect(engine.ingest(obs(.fault, "Dock", source: .unifiedLog, at: t0.addingTimeInterval(60))) == "fault:Dock")
        #expect(engine.finding(crashFP)?.status == .fixed)
    }

    @Test func dnsFlushLinksOnlyToTheFaultFinding() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(obs(.crash, "mDNSResponder", "EXC_CRASH", source: .crashReport))
        #expect(DiagnosisEngine.dnsFlushFingerprint == "fault:mDNSResponder")
        #expect(engine.resolveFingerprint(for: obs(.fault, "mDNSResponder", source: .unifiedLog)) != DiagnosisEngine.dnsFlushFingerprint)
    }

    // MARK: F4 + N6 + F7 — launchd baseline, label normalisation, user redaction

    @Test func launchdBaselineFromOpenFindingsPreventsRecountAfterRestart() throws {
        let output = "PID\tStatus\tLabel\n-\t78\tcom.example.agent\n-\t1\tcom.example.other\n"
        var engine = DiagnosisEngine(machineId: "m1")
        var previous: [String: Int] = [:]
        engine.ingestLaunchd(output: output, previous: &previous, at: t0)
        // Daemon restart: in-memory map lost, seeded from findings.json instead.
        var seeded = engine.launchdBaseline()
        #expect(seeded == ["com.example.agent": 78, "com.example.other": 1])
        engine.ingestLaunchd(output: output, previous: &seeded, at: t0.addingTimeInterval(60))
        #expect(engine.findings.allSatisfy { $0.count == 1 })
        // A changed exit code is a new occurrence.
        engine.ingestLaunchd(output: "-\t3\tcom.example.agent\n-\t1\tcom.example.other\n", previous: &seeded, at: t0.addingTimeInterval(120))
        #expect(engine.finding("launchd:com.example.agent")?.count == 2)
    }

    @Test func launchdLabelsDropApplicationSuffixAndUserName() throws {
        let output = """
        -\t1\tapplication.com.electron.wispr-flow.200817528.200817534
        -\t2\tcom.alice.docsync
        """
        let failures = DiagnosisEngine.launchdFailures(from: output, userName: "alice")
        #expect(failures == ["application.com.electron.wispr-flow": 1, "com.~.docsync": 2])
        var engine = DiagnosisEngine(machineId: "m1")
        var prev: [String: Int] = [:]
        engine.ingestLaunchd(output: output, previous: &prev, at: t0, userName: "alice")
        #expect(engine.findings.allSatisfy { !$0.sample.contains("alice") && !$0.fingerprint.contains("alice") })
    }

    @Test func findingSampleIsSecretRedacted() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(obs(.fault, "cloudd", source: .unifiedLog, sample: "auth Bearer abcdefghijklmnop1234 failed"))
        #expect(engine.findings.first?.sample.contains("abcdefghijklmnop1234") == false)
    }

    // MARK: F5 — caps measured like JS String.length, never splitting a Character

    @Test func capsUseUTF16LengthOnCharacterBoundaries() throws {
        let emoji = String(repeating: "👩‍👩‍👧‍👦", count: 30) // 11 UTF-16 units each
        let capped = DiagnosisEngine.cap(emoji, 64)
        #expect(capped.utf16.count <= 64)
        #expect(capped == String(repeating: "👩‍👩‍👧‍👦", count: 5))
        let combining = String(repeating: "e\u{301}", count: 100) // 2 units, 1 Character each
        #expect(DiagnosisEngine.cap(combining, 5) == String(repeating: "e\u{301}", count: 2))

        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(obs(.crash, emoji, emoji, source: .crashReport, sample: emoji + emoji))
        let f = try #require(engine.findings.first)
        #expect(f.fingerprint.utf16.count <= Finding.maxFingerprint)
        #expect(f.component.utf16.count <= Finding.maxShort)
        #expect(f.sample.utf16.count <= Finding.maxSample)
    }

    // MARK: F6 — stale open findings hidden in the CLI view

    @Test func staleOpenFindingsAreHiddenUnlessAll() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(obs(.crash, "Old", "EXC", source: .crashReport, at: t0))
        engine.ingest(obs(.crash, "New", "EXC", source: .crashReport, at: t0.addingTimeInterval(7 * 86400)))
        let now = t0.addingTimeInterval(7 * 86400 + 3600)
        let view = engine.visibleFindings(now: now, includeAll: false)
        #expect(view.findings.map(\.component) == ["New"])
        #expect(view.staleHidden == 1)
        #expect(engine.visibleFindings(now: now, includeAll: true).findings.count == 2)
    }

    // MARK: F8 — seen-set trimmed by age

    @Test func seenSetDropsPathsNoLongerInTheScanWindow() throws {
        var seen = ReportSeenState()
        _ = seen.fresh(["/a.ips", "/b.ips"])
        _ = seen.fresh(["/a.ips", "/b.ips", "/c.ips"])
        seen.retain(current: ["/b.ips", "/c.ips"]) // /a.ips aged out of the 24 h window
        #expect(seen.seen == ["/b.ips", "/c.ips"])
        #expect(seen.fresh(["/b.ips", "/c.ips"]).isEmpty)
    }

    // MARK: N3 — dirty tracking

    @Test func revisionChangesOnlyOnMutation() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let r0 = engine.revision
        let fp = engine.ingest(obs(.crash, "Finder", "EXC", source: .crashReport))
        #expect(engine.revision > r0)
        let r1 = engine.revision
        engine.refresh(now: t0)
        #expect(engine.revision == r1)
        engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: true, at: t0)
        engine.refresh(now: t0.addingTimeInterval(1800))
        #expect(engine.revision > r1)
    }


}
