import Foundation
import Testing
@testable import HealdCore

struct MeisterBridgeTests {
    private let iso = ISO8601DateFormatter()

    private func run(ts: Date) -> MeisterLastRun {
        MeisterLastRun(
            ts: iso.string(from: ts),
            score: 76,
            err: 0,
            twin: "meisterSiri",
            preferredTwin: "meisterSiri"
        )
    }

    @Test func missingLastJSONShouldRun() {
        #expect(MeisterBridge.shouldRun(last: nil, now: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    @Test func lastFromTodayShouldSkip() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_006_400) // 2023-11-14 18:00 UTC
        let morning = cal.startOfDay(for: now).addingTimeInterval(8 * 3600)
        #expect(MeisterBridge.shouldRun(last: run(ts: morning), now: now, calendar: cal) == false)
    }

    @Test func lastFromYesterdayShouldRun() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_006_400)
        let yesterday = now.addingTimeInterval(-86_400)
        #expect(MeisterBridge.shouldRun(last: run(ts: yesterday), now: now, calendar: cal))
    }

    @Test func parseLastJSONPreferredTwin() throws {
        let json = """
        {"schema":"meister.last/v1","ts":"2026-08-24T11:14:36Z","score":76,"err":0,"twin":"meisterSiri","preferred_twin":"meisterSiri"}
        """.data(using: .utf8)!
        let last = try MeisterBridge.parseLast(json)
        #expect(last.score == 76)
        #expect(last.twin == "meisterSiri")
        #expect(last.preferredTwin == "meisterSiri")
        #expect(last.ts == "2026-08-24T11:14:36Z")
    }

    @Test func resolvePrefersMeisterSiriByDefault() {
        let exists: (String) -> Bool = { $0.hasSuffix("meisterSiri") || $0.hasSuffix("meister") }
        #expect(MeisterBridge.resolveBinary(preferred: nil, exists: exists) == "/opt/homebrew/bin/meisterSiri")
        #expect(MeisterBridge.resolveBinary(preferred: "", exists: exists) == "/opt/homebrew/bin/meisterSiri")
    }

    @Test func resolveHonorsPreferredMeister() {
        let exists: (String) -> Bool = { $0.hasSuffix("/meister") || $0.hasSuffix("meisterSiri") }
        #expect(MeisterBridge.resolveBinary(preferred: "meister", exists: exists) == "/opt/homebrew/bin/meister")
    }

    @Test func resolveNilWhenMissing() {
        #expect(MeisterBridge.resolveBinary(preferred: "meisterSiri", exists: { _ in false }) == nil)
    }

    @Test func skipWhenLockPresent() {
        #expect(MeisterBridge.shouldRun(last: nil, now: Date(), lockExists: true) == false)
    }
}
