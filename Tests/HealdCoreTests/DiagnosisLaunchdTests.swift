import Foundation
import Testing
@testable import HealdCore

private let t0 = Date(timeIntervalSince1970: 1_795_000_000)

/// launchd severity for SIGKILL/jetsam.
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
}
