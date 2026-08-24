import Foundation
import HealdCore
import OSLog

/// Optional daily batch-maintain via meisterSiri (or meister). No binary → skip; heald stays native.
enum MeisterBridgeRunner {
    struct Outcome: Codable, Sendable {
        var ts: String
        var action: String
        var binary: String?
        var exitCode: Int32?
        var durationSec: Int?
        var detail: String?
    }

    static var lastJSONURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meister/last.json")
    }

    static var lockURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meister/meister.lock")
    }

    static var preferredTwinURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meister/preferred_twin")
    }

    static var statusURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/meister_bridge.json")
    }

    static func loadLast() -> MeisterLastRun? {
        guard let data = try? Data(contentsOf: lastJSONURL) else { return nil }
        return try? MeisterBridge.parseLast(data)
    }

    static func preferredTwin() -> String? {
        guard let raw = try? String(contentsOf: preferredTwinURL, encoding: .utf8) else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Returns true when MeisterSiri/meister ran (or already ran today). False → caller may use native quick.
    @discardableResult
    static func tick(force: Bool = false, timeoutSeconds: TimeInterval = 1200) -> Outcome {
        let now = Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let ts = iso.string(from: now)

        let last = loadLast()
        let preferred = preferredTwin() ?? last?.preferredTwin
        let binary = MeisterBridge.resolveBinary(preferred: preferred) { FileManager.default.isExecutableFile(atPath: $0) }

        func finish(_ o: Outcome) -> Outcome {
            writeStatus(o)
            Logger.maintenance.info("MeisterBridge \(o.action) \(o.binary ?? "") \(o.detail ?? "")")
            return o
        }

        guard let binary else {
            return finish(Outcome(ts: ts, action: "skipped_no_binary", binary: nil, exitCode: nil, durationSec: nil, detail: "meisterSiri not on PATH"))
        }

        let lockExists = FileManager.default.fileExists(atPath: lockURL.path)
        if !force, !MeisterBridge.shouldRun(last: last, now: now, lockExists: lockExists) {
            let action = lockExists ? "skipped_lock" : "skipped_already_today"
            return finish(Outcome(ts: ts, action: action, binary: binary, exitCode: nil, durationSec: nil, detail: last?.ts))
        }

        let started = Date()
        let result = ShellRunner.run(binary, arguments: ["--auto", "-q"], timeoutSeconds: timeoutSeconds)
        let dur = Int(Date().timeIntervalSince(started))
        let action = result.succeeded ? "ran" : "failed"
        return finish(Outcome(
            ts: ts,
            action: action,
            binary: binary,
            exitCode: result.exitCode,
            durationSec: dur,
            detail: result.succeeded ? nil : String(result.errorOutput.prefix(400))
        ))
    }

    private static func writeStatus(_ o: Outcome) {
        let dir = statusURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(o) else { return }
        try? data.write(to: statusURL, options: .atomic)
    }
}
