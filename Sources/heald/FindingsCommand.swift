import ArgumentParser
import Foundation
import HealdCore

// MARK: - Findings

/// `heald findings` — the device error picture from ~/.heald/data/findings.json (read-only).
struct FindingsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "findings",
        abstract: "List open device findings (crashes, panics, faults, launchd jobs)"
    )

    @Flag(name: .long, help: "Include fixed findings and open ones quiet for more than 7 days")
    var all: Bool = false

    @Flag(name: .long, help: "Print findings as heald.findings/v1 JSON")
    var json: Bool = false

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        // Read-only: never moves or rewrites the daemon's file.
        let engine = FindingsFile.load(
            from: FindingsStore.fileURL, machineId: DeviceIdentity.machineId(), quarantineCorrupt: false
        )
        let (list, staleHidden) = engine.visibleFindings(now: Date(), includeAll: all)
        let staleNote = staleHidden > 0 ? ", \(staleHidden) stale hidden (quiet > 7 days, use --all)" : ""

        if json {
            let data = try DiagnosisEngine.encoder(pretty: true).encode(list)
            print(String(decoding: data, as: UTF8.self))
            return
        }
        guard !list.isEmpty else {
            print("No \(all ? "" : "open ")findings (unparsed inputs: \(engine.unparsed))\(staleNote)")
            return
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        print("SEVERITY  STATUS     COUNT  LAST SEEN             LINKED        FINGERPRINT")
        for f in list {
            print([
                f.severity.rawValue.padding(toLength: 8, withPad: " ", startingAt: 0),
                f.status.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0),
                String(f.count).padding(toLength: 5, withPad: " ", startingAt: 0),
                iso.string(from: f.lastSeen).padding(toLength: 20, withPad: " ", startingAt: 0),
                (f.linkedAction ?? "-").padding(toLength: 12, withPad: " ", startingAt: 0),
                f.fingerprint,
            ].joined(separator: "  "))
        }
        print("\(list.count) finding(s)\(staleNote), unparsed inputs: \(engine.unparsed) — \(FindingsStore.fileURL.path)")
    }
}
