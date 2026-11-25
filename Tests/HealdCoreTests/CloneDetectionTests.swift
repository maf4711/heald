import Foundation
import Testing
@testable import HealdCore

struct CloneDetectionDecisionTests {
    let here = "11111111-2222-3333-4444-555555555555"
    let other = "409C591A-AAAA-BBBB-CCCC-DDDDDDDDDDDD"

    @Test func matchingHardwareUUIDKeeps() {
        #expect(CloneDetection.decide(storedHardwareUUID: here, storedDeviceId: here, currentHardwareUUID: here) == .keep)
    }

    @Test func matchIsCaseAndWhitespaceInsensitive() {
        #expect(CloneDetection.decide(
            storedHardwareUUID: " \(here.lowercased())\n", storedDeviceId: "x", currentHardwareUUID: here
        ) == .keep)
    }

    @Test func differentHardwareUUIDReenrolls() {
        #expect(CloneDetection.decide(storedHardwareUUID: other, storedDeviceId: other, currentHardwareUUID: here) == .reenroll)
    }

    @Test func storedHardwareUUIDWinsOverDeviceId() {
        // deviceId happens to equal this Mac, but the record says it was enrolled on other hardware.
        #expect(CloneDetection.decide(storedHardwareUUID: other, storedDeviceId: here, currentHardwareUUID: here) == .reenroll)
    }

    @Test func unknownCurrentUUIDNeverReenrolls() {
        #expect(CloneDetection.decide(storedHardwareUUID: other, storedDeviceId: other, currentHardwareUUID: nil) == .keep)
        #expect(CloneDetection.decide(storedHardwareUUID: other, storedDeviceId: other, currentHardwareUUID: "  ") == .keep)
    }

    @Test func nilStoredUUIDBackfillsInsteadOfRotating() {
        #expect(CloneDetection.decide(storedHardwareUUID: nil, storedDeviceId: here.lowercased(), currentHardwareUUID: here) == .backfill)
        #expect(CloneDetection.decide(storedHardwareUUID: "", storedDeviceId: here, currentHardwareUUID: here) == .backfill)
        #expect(CloneDetection.decide(storedHardwareUUID: nil, storedDeviceId: other, currentHardwareUUID: here) == .backfill)
    }

    @Test func nilStoredAndNilCurrentKeeps() {
        #expect(CloneDetection.decide(storedHardwareUUID: nil, storedDeviceId: other, currentHardwareUUID: nil) == .keep)
    }

    @Test func idPrefixIsPathSafe() {
        #expect(CloneDetection.idPrefix("409C591A-1234") == "409C591A")
        #expect(CloneDetection.idPrefix("../../etc") == "etc")
        #expect(CloneDetection.idPrefix("/..") == "unknown")
    }

    @Test func archiveNameUsesUTCStamp() {
        let t = Date(timeIntervalSince1970: 1_763_726_400) // 2025-11-21 12:00:00 UTC
        #expect(CloneDetection.archiveDirectoryName(sourceDeviceId: other, now: t) == ".cloned-409C591A-20251121-120000")
    }
}

struct CloneDetectionRelocationTests {
    let fm = FileManager.default

    func makeHealdDir() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("heald-clone-\(UUID().uuidString)")
        try fm.createDirectory(at: root.appendingPathComponent("data"), withIntermediateDirectories: true)
        return root
    }

    func write(_ dir: URL, _ rel: String, _ body: String = "x") throws {
        try Data(body.utf8).write(to: dir.appendingPathComponent(rel))
    }

    @Test func movesPerDeviceFilesAndKeepsHistory() throws {
        let heald = try makeHealdDir()
        defer { try? fm.removeItem(at: heald) }
        let t = Date(timeIntervalSince1970: 1_763_726_400)
        for rel in ["device.json", "policy.json", "data/heal_reports.ndjson", "data/heal_report_cursor",
                    "data/findings.json", "data/cloud_push_cursor", "data/siem_cursor",
                    "data/activity.ndjson", "data/metrics.db"] {
            try write(heald, rel, rel)
        }

        let r = try CloneDetection.relocate(healdDir: heald, sourceDeviceId: "409C591A-XYZ", now: t,
                                            commit: { try write(heald, "device.json", "new") })

        #expect(r.archiveDirectory.lastPathComponent == ".cloned-409C591A-20251121-120000")
        #expect(r.archiveDirectory.deletingLastPathComponent().lastPathComponent == "data")
        #expect(Set(r.moved) == ["device.json", "data/heal_reports.ndjson", "data/heal_report_cursor",
                                 "data/findings.json", "data/cloud_push_cursor", "data/siem_cursor"])
        #expect(try String(contentsOf: heald.appendingPathComponent("device.json"), encoding: .utf8) == "new")
        for rel in r.moved {
            if rel != "device.json" { #expect(!fm.fileExists(atPath: heald.appendingPathComponent(rel).path)) }
            let moved = r.archiveDirectory.appendingPathComponent((rel as NSString).lastPathComponent)
            #expect(try String(contentsOf: moved, encoding: .utf8) == rel) // moved intact, not deleted
        }
        for kept in ["policy.json", "data/activity.ndjson", "data/metrics.db"] {
            #expect(fm.fileExists(atPath: heald.appendingPathComponent(kept).path))
        }
    }

    @Test func secondRelocationInSameSecondGetsOwnDirectory() throws {
        let heald = try makeHealdDir()
        defer { try? fm.removeItem(at: heald) }
        let t = Date(timeIntervalSince1970: 1_763_726_400)
        try write(heald, "device.json", "first")
        let a = try CloneDetection.relocate(healdDir: heald, sourceDeviceId: "AAAA", now: t,
                                            commit: { try write(heald, "device.json", "second") })
        let b = try CloneDetection.relocate(healdDir: heald, sourceDeviceId: "AAAA", now: t,
                                            commit: { try write(heald, "device.json", "third") })

        #expect(a.archiveDirectory != b.archiveDirectory)
        #expect(b.archiveDirectory.lastPathComponent.hasSuffix("-2"))
        #expect(try String(contentsOf: a.archiveDirectory.appendingPathComponent("device.json"), encoding: .utf8) == "first")
        #expect(try String(contentsOf: b.archiveDirectory.appendingPathComponent("device.json"), encoding: .utf8) == "second")
    }

    @Test func nothingToMoveStillLeavesTrace() throws {
        let heald = try makeHealdDir()
        defer { try? fm.removeItem(at: heald) }
        let r = try CloneDetection.relocate(healdDir: heald, sourceDeviceId: "BBBB")
        #expect(r.moved.isEmpty)
        #expect(fm.fileExists(atPath: r.archiveDirectory.path))
    }

    @Test func listCoversOutboxFindingsAndCursors() {
        let list = Set(CloneDetection.perDeviceFiles)
        for must in ["device.json", "approvals.json", "data/heal_reports.ndjson", "data/heal_report_cursor", "data/findings.json",
                     "data/cloud_push_cursor", "data/siem_cursor", "data/error_scanner_seen.json"] {
            #expect(list.contains(must))
        }
        #expect(!list.contains("data/activity.ndjson"))
        #expect(!list.contains("data/metrics.db"))
        #expect(!list.contains("policy.json"))
    }

    struct Boom: Error {}

    func seedClone(_ heald: URL) throws -> [String] {
        let rels = ["device.json", "approvals.json", "data/heal_reports.ndjson", "data/findings.json", "data/siem_cursor"]
        for rel in rels { try write(heald, rel, rel) }
        return rels
    }

    @Test func failureMidMoveRollsBackAndKeepsDeviceJson() throws {
        let heald = try makeHealdDir()
        defer { try? fm.removeItem(at: heald) }
        let rels = try seedClone(heald)
        var calls = 0
        var committed = false
        #expect(throws: Boom.self) {
            try CloneDetection.relocate(
                healdDir: heald, sourceDeviceId: "CCCC",
                move: { src, dst in
                    calls += 1
                    if calls == 2 { throw Boom() }
                    try FileManager.default.moveItem(at: src, to: dst)
                },
                commit: { committed = true }
            )
        }
        #expect(!committed)
        for rel in rels { // device.json never left; the first moved file is back
            #expect(try String(contentsOf: heald.appendingPathComponent(rel), encoding: .utf8) == rel)
        }
    }

    @Test func failingCommitRollsBackEverything() throws {
        let heald = try makeHealdDir()
        defer { try? fm.removeItem(at: heald) }
        let rels = try seedClone(heald)
        #expect(throws: Boom.self) {
            try CloneDetection.relocate(healdDir: heald, sourceDeviceId: "DDDD", commit: { throw Boom() })
        }
        for rel in rels {
            #expect(try String(contentsOf: heald.appendingPathComponent(rel), encoding: .utf8) == rel)
        }
    }

    @Test func archiveDirectoryCreationNeverReusesExistingDir() throws {
        let heald = try makeHealdDir()
        defer { try? fm.removeItem(at: heald) }
        let data = heald.appendingPathComponent("data")
        let a = try CloneDetection.makeArchiveDirectory(in: data, name: ".cloned-X", fileManager: fm)
        let b = try CloneDetection.makeArchiveDirectory(in: data, name: ".cloned-X", fileManager: fm)
        let c = try CloneDetection.makeArchiveDirectory(in: data, name: ".cloned-X", fileManager: fm)
        #expect([a, b, c].map(\.lastPathComponent) == [".cloned-X", ".cloned-X-2", ".cloned-X-3"])
    }

    @Test func identityLockRunsBodyAndCreatesLockFile() throws {
        let heald = try makeHealdDir()
        defer { try? fm.removeItem(at: heald) }
        let lock = heald.appendingPathComponent(".identity.lock")
        let v = IdentityLock.withLock(at: lock) { 42 }
        #expect(v == 42)
        #expect(fm.fileExists(atPath: lock.path))
        // Released after the body: a second acquisition does not deadlock.
        #expect(IdentityLock.withLock(at: lock) { 7 } == 7)
    }
}
