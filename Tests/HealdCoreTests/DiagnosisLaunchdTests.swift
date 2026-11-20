import Foundation
import Testing
@testable import HealdCore

private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

/// launchd severity for SIGKILL/jetsam and recovery → fixed.
struct DiagnosisLaunchdTests {
    @Test func appleJobKilledBySigkillIsWarning() throws {
        var e = DiagnosisEngine(machineId: "m1")
        var prev: [String: Int] = [:]
        e.ingestLaunchd(output: "-\t-9\tcom.apple.knowledgeconstructiond\n", previous: &prev, at: t0)
        #expect(try #require(e.findings.first).severity == .warning)
    }

    @Test func nonAppleSigkillAndAppleExitCodesStayError() throws {
        var e = DiagnosisEngine(machineId: "m1")
        var prev: [String: Int] = [:]
        e.ingestLaunchd(output: "-\t-9\tcom.example.agent\n-\t1\tcom.apple.Dock.agent\n", previous: &prev, at: t0)
        #expect(e.finding("launchd:com.example.agent")?.severity == .error)
        #expect(e.finding("launchd:com.apple.Dock.agent")?.severity == .error)
    }

    @Test func recoveredJobIsFixedThenRecurring() throws {
        var e = DiagnosisEngine(machineId: "m1")
        var prev: [String: Int] = [:]
        e.ingestLaunchd(output: "-\t78\tcom.example.agent\n", previous: &prev, at: t0)
        let fp = "launchd:com.example.agent"
        #expect(e.finding(fp)?.status == .open)

        e.ingestLaunchd(output: "-\t0\tcom.example.agent\n", previous: &prev, at: t0.addingTimeInterval(60))
        let fixed = try #require(e.finding(fp))
        #expect(fixed.status == .fixed)
        #expect(fixed.lastSeen == t0)
        #expect(fixed.linkedAction == nil)
        #expect(e.launchdBaseline().isEmpty)

        e.ingestLaunchd(output: "-\t78\tcom.example.agent\n", previous: &prev, at: t0.addingTimeInterval(120))
        let again = try #require(e.finding(fp))
        #expect(again.status == .recurring)
        #expect(again.recurrenceCount == 1)
        #expect(again.count == 2)
    }

    @Test func runningJobWithoutStatusLineIsFixedButUnlistedJobStaysOpen() {
        var e = DiagnosisEngine(machineId: "m1")
        var prev: [String: Int] = [:]
        e.ingestLaunchd(output: "-\t2\tcom.example.a\n-\t3\tcom.example.b\n", previous: &prev, at: t0)
        // a: still listed, no longer failing (running, pid shown) → fixed; b: unloaded → unknown, stays open
        e.ingestLaunchd(output: "4711\t0\tcom.example.a\n", previous: &prev, at: t0.addingTimeInterval(60))
        #expect(e.finding("launchd:com.example.a")?.status == .fixed)
        #expect(e.finding("launchd:com.example.b")?.status == .open)
    }
}
