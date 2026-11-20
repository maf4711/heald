import Foundation
import Testing
@testable import HealdCore

private let t0 = Date(timeIntervalSince1970: 1_795_000_000) // 2026-11-18

private func crash(
    _ component: String,
    _ exception: String = "EXC_BAD_ACCESS",
    at: Date = t0
) -> Observation {
    Observation(
        category: .crash,
        component: component,
        signature: exception,
        source: .crashReport,
        at: at,
        sample: "\(component) crashed: \(exception)"
    )
}

private func fault(_ component: String, at: Date = t0) -> Observation {
    Observation(
        category: .fault,
        component: component,
        signature: "",
        source: .unifiedLog,
        at: at,
        sample: "fault in \(component)"
    )
}

private func minutes(_ m: Double) -> TimeInterval { m * 60 }

struct DiagnosisEngineTests {
    // MARK: criterion 1 — dedupe, count, severity table

    @Test func fiftyIdenticalCrashesYieldOneFindingWithCount50() throws { // (a)
        var engine = DiagnosisEngine(machineId: "m1")
        for i in 0..<50 {
            engine.ingest(crash("Finder", at: t0.addingTimeInterval(Double(i) * 60)))
        }
        #expect(engine.findings.count == 1)
        let f = try #require(engine.findings.first)
        #expect(f.fingerprint == "crash:Finder:EXC_BAD_ACCESS")
        #expect(f.count == 50)
        #expect(f.firstSeen == t0)
        #expect(f.lastSeen == t0.addingTimeInterval(49 * 60))
        #expect(f.status == .open)
        #expect(f.category == .crash)
        #expect(f.component == "Finder")
    }

    @Test func differentExceptionTypesAreDistinctFindings() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(crash("Finder", "EXC_BAD_ACCESS"))
        engine.ingest(crash("Finder", "EXC_CRASH"))
        #expect(engine.findings.count == 2)
    }

    @Test func severityTableIsFixed() throws {
        #expect(DiagnosisEngine.severity(category: .panic, component: "kernel") == .critical)
        #expect(DiagnosisEngine.severity(category: .crash, component: "Finder") == .warning)
        #expect(DiagnosisEngine.severity(category: .crash, component: "Xcode") == .error)
        #expect(DiagnosisEngine.severity(category: .fault, component: "mds") == .warning)
        #expect(DiagnosisEngine.severity(category: .launchdJob, component: "com.x") == .error)
    }

    @Test func crashAndFaultSameComponentMergeIntoOneFinding() throws { // (b)
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(crash("WindowServer"))
        engine.ingest(fault("WindowServer", at: t0.addingTimeInterval(30)))
        #expect(engine.findings.count == 1)
        let f = try #require(engine.findings.first)
        #expect(f.sources == ["crash_report", "unified_log"])
        #expect(f.count == 2)
        #expect(f.severity == .error)
    }

    @Test func faultWithoutCrashGetsOwnFingerprint() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(fault("mDNSResponder"))
        #expect(engine.findings.first?.fingerprint == "fault:mDNSResponder")
        #expect(engine.findings.first?.severity == .warning)
    }

    // MARK: criterion 2 — lifecycle open → fixed → recurring

    @Test func healedFindingBecomesFixedAfterQuietWindow() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let fp = engine.ingest(crash("Finder"))
        engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: true, at: t0.addingTimeInterval(60))
        engine.refresh(now: t0.addingTimeInterval(60 + minutes(29)))
        #expect(engine.finding(fp)?.status == .open)
        engine.refresh(now: t0.addingTimeInterval(60 + minutes(30)))
        let f = try #require(engine.finding(fp))
        #expect(f.status == .fixed)
        #expect(f.linkedAction == "app_restart")
    }

    @Test func newOccurrenceAfterFixedIsRecurring() throws { // (c)
        var engine = DiagnosisEngine(machineId: "m1")
        let fp = engine.ingest(crash("Finder"))
        engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: true, at: t0)
        engine.refresh(now: t0.addingTimeInterval(minutes(30)))
        #expect(engine.finding(fp)?.status == .fixed)
        engine.ingest(crash("Finder", at: t0.addingTimeInterval(minutes(31))))
        let f = try #require(engine.finding(fp))
        #expect(f.status == .recurring)
        #expect(f.recurrenceCount == 1)
        #expect(f.count == 2)
        #expect(f.linkedAction == "app_restart")
    }

    @Test func occurrenceInsideQuietWindowKeepsFindingOpen() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let fp = engine.ingest(crash("Finder"))
        engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: true, at: t0)
        engine.ingest(crash("Finder", at: t0.addingTimeInterval(minutes(10))))
        engine.refresh(now: t0.addingTimeInterval(minutes(45)))
        #expect(engine.finding(fp)?.status == .open)
        #expect(engine.finding(fp)?.recurrenceCount == 0)
    }

    @Test func failedHealLinksActionButNeverFixes() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let fp = engine.ingest(crash("Dock"))
        engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: false, at: t0)
        engine.refresh(now: t0.addingTimeInterval(minutes(120)))
        #expect(engine.finding(fp)?.status == .open)
        #expect(engine.finding(fp)?.linkedAction == "app_restart")
    }

    @Test func recurringFindingCanBeFixedAgain() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let fp = engine.ingest(crash("Finder"))
        engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: true, at: t0)
        engine.refresh(now: t0.addingTimeInterval(minutes(31)))
        engine.ingest(crash("Finder", at: t0.addingTimeInterval(minutes(40))))
        engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: true, at: t0.addingTimeInterval(minutes(41)))
        engine.refresh(now: t0.addingTimeInterval(minutes(80)))
        #expect(engine.finding(fp)?.status == .fixed)
        #expect(engine.finding(fp)?.recurrenceCount == 1)
    }

    // MARK: criterion 4 — launchd + panic sources

    @Test func launchdNonZeroExitIsAnErrorFinding() throws { // (d)
        let output = """
        PID\tStatus\tLabel
        -\t78\tcom.example.agent
        123\t0\tcom.example.running
        -\t0\tcom.example.clean
        92264\t-15\tcom.example.unloaded
        """
        var engine = DiagnosisEngine(machineId: "m1")
        var previous: [String: Int] = [:]
        engine.ingestLaunchd(output: output, previous: &previous, at: t0)
        #expect(engine.findings.count == 1)
        let f = try #require(engine.findings.first)
        #expect(f.category == .launchdJob)
        #expect(f.severity == .error)
        #expect(f.component == "com.example.agent")
        #expect(f.fingerprint == "launchd:com.example.agent")
        #expect(f.sources == ["launchd"])
        #expect(f.sample.contains("78"))

        // Same state on the next scan is not a new occurrence.
        engine.ingestLaunchd(output: output, previous: &previous, at: t0.addingTimeInterval(60))
        #expect(engine.findings.first?.count == 1)
    }

    @Test func launchdListParserHandlesSignalsHeaderAndMalformedRows() throws {
        let output = """
        PID\tStatus\tLabel
        -\t2\tcom.example.docsync
        4711\t-9\tcom.example.killed
        -\t-15\tcom.example.sigterm
        garbage line
        -\tx\tcom.example.nonnumeric
        """
        #expect(DiagnosisEngine.launchdFailures(from: output) == [
            "com.example.docsync": 2, "com.example.killed": -9,
        ])
    }

    @Test func panicReportIsCriticalWithStableFingerprint() throws {
        let a = DiagnosisEngine.classifyReport(
            filename: "panic-full-2026-11-20-101500.0002.panic",
            contents: #"{"bug_type":"210"}"# + "\n" +
                #"{"panicString":"panic(cpu 3 caller 0xfffffe0012345678): watchdog timeout: no checkins from watchdogd in 92 seconds\n"}"#,
            at: t0
        )
        let b = DiagnosisEngine.classifyReport(
            filename: "panic-full-2026-11-21-111111.0001.panic",
            contents: "panic(cpu 7 caller 0xfffffe00aaaabbbb): watchdog timeout: no checkins from watchdogd in 181 seconds",
            at: t0
        )
        let pa = try #require(a)
        let pb = try #require(b)
        #expect(pa.category == .panic)
        #expect(pa.source == .panicReport)
        #expect(pa.component == "kernel")
        #expect(DiagnosisEngine.fingerprint(for: pa) == DiagnosisEngine.fingerprint(for: pb))
        #expect(DiagnosisEngine.fingerprint(for: pa).hasPrefix("panic:kernel:watchdog timeout"))
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(pa)
        engine.ingest(pb)
        #expect(engine.findings.count == 1)
        #expect(engine.findings.first?.severity == .critical)
    }

    @Test func ipsCrashReportParses() throws {
        let ips = #"{"app_name":"Finder","bug_type":"309","name":"Finder"}"# + "\n" + """
        {
          "procName" : "Finder",
          "exception" : {"codes":"0x0000000000000001, 0x0","rawCodes":[1,0],"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"}
        }
        """
        let o = try #require(DiagnosisEngine.classifyReport(filename: "Finder-2026-11-20-101500.ips", contents: ips, at: t0))
        #expect(o.category == .crash)
        #expect(o.component == "Finder")
        #expect(o.signature == "EXC_BAD_ACCESS")
        #expect(DiagnosisEngine.fingerprint(for: o) == "crash:Finder:EXC_BAD_ACCESS")
    }

    @Test func legacyCrashAndDiagReportsParse() throws {
        let crashText = "Process:  Dock [123]\nException Type:  EXC_CRASH (SIGABRT)\n"
        let c = try #require(DiagnosisEngine.classifyReport(filename: "Dock_2026-11-20-101500_host.crash", contents: crashText, at: t0))
        #expect(c.component == "Dock")
        #expect(c.signature == "EXC_CRASH")

        let diag = "Command:          suggestd\nEvent:            disk writes\n"
        let d = try #require(DiagnosisEngine.classifyReport(filename: "suggestd_2026-11-19-190543_CM-X.diag", contents: diag, at: t0))
        #expect(d.category == .fault)
        #expect(d.source == .diagnosticReport)
        #expect(d.component == "suggestd")
        #expect(DiagnosisEngine.fingerprint(for: d) == "fault:suggestd:disk_writes")
    }

    @Test func reportFilenameParserHandlesHyphenAndUnderscore() throws {
        #expect(DiagnosisEngine.processName(fromReportFilename: "Finder-2026-11-20-101500.ips") == "Finder")
        #expect(DiagnosisEngine.processName(fromReportFilename: "bird_2026-11-20-111520_CM-CFMQ2D029F-2.diag") == "bird")
        #expect(DiagnosisEngine.processName(fromReportFilename: "x.cpu_resource.diag") == "x.cpu_resource")
    }

    // MARK: criterion 5 — malformed input

    @Test func malformedInputIsCountedUnparsedAndNeverCrashes() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingestReport(filename: "Finder-2026-11-20-101500.ips", contents: "", at: t0)
        let garbage = String(decoding: (0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }, as: UTF8.self)
        engine.ingestReport(filename: "Dock-2026-11-20-101500.ips", contents: garbage, at: t0)
        engine.ingestReport(filename: "Dock_2026-11-20-101500_host.crash", contents: garbage, at: t0)
        let counts = engine.ingestFaultLines([
            "Filtering the log data using \"messageType == fault\"",
            "Timestamp               Ty Process[PID:TID]",
            "garbage-without-process",
            "",
        ], at: t0)
        #expect(counts.isEmpty)
        #expect(engine.findings.isEmpty)
        #expect(engine.unparsed == 4)
    }

    @Test func faultLinesAreCountedPerProcess() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        let counts = engine.ingestFaultLines([
            "2026-11-20 10:15:00.123 Fa  mDNSResponder[123:456] bad thing",
            "2026-11-20 10:15:01.123 Fa  mDNSResponder[123:456] bad thing again",
            "2026-11-20 10:15:02.123 Fa  cloudd[9:10] oops",
        ], at: t0)
        #expect(counts == ["mDNSResponder": 2, "cloudd": 1])
        #expect(engine.finding("fault:mDNSResponder")?.count == 2)
        #expect(engine.finding("fault:cloudd")?.count == 1)
    }

    @Test func freshLinesSkipLinesSeenInPreviousScan() throws {
        var seen: Set<String> = []
        #expect(DiagnosisEngine.freshLines(["a", "b"], seen: &seen) == ["a", "b"])
        #expect(DiagnosisEngine.freshLines(["b", "c"], seen: &seen) == ["c"])
    }

    // MARK: edge cases

    @Test func primedStartEmitsZeroFindings() throws { // (e)
        var seen = ReportSeenState()
        let old = (0..<1000).map { "/Library/Logs/DiagnosticReports/Finder-\($0).ips" }
        var engine = DiagnosisEngine(machineId: "m1")
        for path in seen.fresh(old) {
            engine.ingestReport(filename: path, contents: "Exception Type: EXC_CRASH", at: t0)
        }
        #expect(seen.primed)
        #expect(engine.findings.isEmpty)
        #expect(seen.fresh(old + ["/new.ips"]) == ["/new.ips"])
    }

    @Test func fingerprintRedactsUserPaths() throws { // (f)
        let fp = DiagnosisEngine.fingerprint(category: .crash, component: "/Users/alice/x", signature: "EXC_CRASH")
        #expect(fp.contains("/Users/~/x"))
        #expect(!fp.contains("alice"))
        var engine = DiagnosisEngine(machineId: "m1")
        engine.ingest(Observation(
            category: .fault, component: "/Users/alice/bin/tool", signature: "",
            source: .unifiedLog, at: t0, sample: "open /Users/alice/secret failed"
        ))
        let f = try #require(engine.findings.first)
        #expect(!f.component.contains("alice"))
        #expect(!f.sample.contains("alice"))
    }

    @Test func evictionDropsOldestFixedAndKeepsAllOpen() throws { // (g)
        var engine = DiagnosisEngine(machineId: "m1")
        var fixed: [String] = []
        for i in 0..<201 {
            let fp = engine.ingest(crash("Fixed\(i)", at: t0.addingTimeInterval(Double(i))))
            engine.recordHeal(fingerprint: fp, action: "app_restart", succeeded: true, at: t0.addingTimeInterval(Double(i)))
            fixed.append(fp)
        }
        engine.refresh(now: t0.addingTimeInterval(minutes(60)))
        var open: [String] = []
        for i in 0..<300 {
            open.append(engine.ingest(crash("Open\(i)", at: t0.addingTimeInterval(minutes(61)))))
        }
        #expect(engine.findings.count == 500)
        for fp in open { #expect(engine.finding(fp)?.status == .open) }
        #expect(engine.finding(fixed[0]) == nil) // oldest fixed evicted first
        #expect(engine.finding(fixed[200]) != nil)
    }

    @Test func hardCapEvictsOldestOpenWhenNothingIsFixed() throws {
        var engine = DiagnosisEngine(machineId: "m1")
        for i in 0..<501 { engine.ingest(crash("Open\(i)", at: t0.addingTimeInterval(Double(i)))) }
        #expect(engine.findings.count == 500)
        #expect(engine.finding("crash:Open0:EXC_BAD_ACCESS") == nil)
        #expect(engine.finding("crash:Open500:EXC_BAD_ACCESS") != nil)
    }
}
