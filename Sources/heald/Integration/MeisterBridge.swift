import Foundation
import ServiceLifecycle
import OSLog

/// Reads `~/.meister/last.json` (batch-maintain handshake) and optionally
/// triggers the preferred Meister twin (`meisterSiri` or `meister --quick`).
///
/// Contract (docs/PRODUCT.md in homebrew-meister):
/// - heald = continuous observe
/// - meister = batch maintain
struct MeisterBridgeService: Service {
    let activityLog: ActivityLog

    /// How often to re-check last.json (seconds).
    private let pollSeconds: Int = 900 // 15 min
    /// Trigger maintain if last run older than this (seconds).
    private let staleSeconds: Int = 86_400 // 24h
    /// If last run had errors, re-trigger after this age (seconds).
    private let errorRetrySeconds: Int = 3_600 // 1h
    /// Min gap between triggered runs (seconds).
    private let cooldownSeconds: Int = 3_600

    private let lastJSONPath: URL
    private let preferredTwinPath: URL
    private let cooldownMarker: URL

    init(activityLog: ActivityLog) {
        self.activityLog = activityLog
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.lastJSONPath = home.appendingPathComponent(".meister/last.json")
        self.preferredTwinPath = home.appendingPathComponent(".meister/preferred_twin")
        let healdData = home.appendingPathComponent(".heald/data")
        try? FileManager.default.createDirectory(at: healdData, withIntermediateDirectories: true)
        self.cooldownMarker = healdData.appendingPathComponent("meister_bridge_last_trigger")
    }

    func run() async throws {
        Logger.lifecycle.info("MeisterBridge started — watching ~/.meister/last.json")
        // First tick soon after start (don't wait full poll)
        await tick()
        while true {
            try await Task.sleep(for: .seconds(pollSeconds))
            await tick()
        }
    }

    // MARK: - Tick

    private func tick() async {
        let snap = Self.readLastJSON(at: lastJSONPath)
        let preferred = Self.preferredMaintainCLI(preferredTwinPath: preferredTwinPath)

        if let snap {
            Logger.lifecycle.debug(
                "Meister last: score=\(snap.score.map(String.init) ?? "?") err=\(snap.err) age=\(Int(snap.ageSeconds))s twin=\(snap.twin ?? "?")"
            )
        } else {
            Logger.lifecycle.debug("Meister last.json missing or unreadable")
        }

        // Persist a small snapshot for doctor / debug
        Self.writeHealdView(snap: snap, preferred: preferred)

        guard shouldTrigger(snap: snap) else { return }
        if inCooldown() { return }

        await triggerMaintain(cli: preferred, reason: triggerReason(snap: snap))
        markTriggered()
    }

    private func inCooldown() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cooldownMarker.path),
              let m = attrs[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(m) < Double(cooldownSeconds)
    }

    private func markTriggered() {
        try? "\(Date().timeIntervalSince1970)".write(to: cooldownMarker, atomically: true, encoding: .utf8)
    }

    private func shouldTrigger(snap: MeisterLastSnapshot?) -> Bool {
        guard let snap else { return true } // missing → run once
        if snap.ageSeconds > Double(staleSeconds) { return true }
        if snap.err > 0 && snap.ageSeconds > Double(errorRetrySeconds) { return true }
        return false
    }

    private func triggerReason(snap: MeisterLastSnapshot?) -> String {
        guard let snap else { return "missing last.json" }
        if snap.ageSeconds > Double(staleSeconds) {
            return "stale (\(Int(snap.ageSeconds / 3600))h)"
        }
        if snap.err > 0 {
            return "err=\(snap.err) age=\(Int(snap.ageSeconds))s"
        }
        return "policy"
    }

    private func triggerMaintain(cli: String, reason: String) async {
        guard let exe = ShellRunner.findExecutable(cli) else {
            Logger.lifecycle.warning("MeisterBridge: \(cli) not on PATH — skip trigger")
            try? await activityLog.log(event: ActivityEvent(
                type: .maintenanceStarted,
                summary: "MeisterBridge skip: \(cli) not found (\(reason))"
            ))
            return
        }

        Logger.lifecycle.info("MeisterBridge: triggering \(cli) --quick -q (\(reason))")
        try? await activityLog.log(event: ActivityEvent(
            type: .maintenanceStarted,
            summary: "MeisterBridge → \(cli) --quick -q (\(reason))"
        ))

        // Run off the cooperative pool so we don't block the service loop hard
        let result = await Task.detached {
            ShellRunner.run(exe, arguments: ["--quick", "-q"])
        }.value

        let summary = result.succeeded
            ? "MeisterBridge \(cli) ok (exit \(result.exitCode))"
            : "MeisterBridge \(cli) exit \(result.exitCode): \(result.errorOutput.prefix(200))"
        try? await activityLog.log(event: ActivityEvent(
            type: result.succeeded ? .maintenanceCompleted : .maintenanceStarted,
            summary: String(summary)
        ))
        Logger.lifecycle.info("\(summary)")
    }

    // MARK: - Read helpers

    struct MeisterLastSnapshot: Sendable {
        let ts: Date?
        let score: Int?
        let err: Int
        let warn: Int
        let twin: String?
        let version: String?
        let profile: String?
        let ageSeconds: TimeInterval
    }

    static func readLastJSON(at url: URL) -> MeisterLastSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let score = obj["score"] as? Int
        let err = (obj["err"] as? Int) ?? 0
        let warn = (obj["warn"] as? Int) ?? 0
        let twin = obj["twin"] as? String
        let version = obj["version"] as? String
        let profile = obj["profile"] as? String

        var tsDate: Date?
        if let ts = obj["ts"] as? String {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            tsDate = f.date(from: ts)
            if tsDate == nil {
                f.formatOptions = [.withInternetDateTime]
                tsDate = f.date(from: ts)
            }
        }
        let age: TimeInterval
        if let tsDate {
            age = Date().timeIntervalSince(tsDate)
        } else {
            // fall back to file mtime
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let m = attrs[.modificationDate] as? Date {
                age = Date().timeIntervalSince(m)
            } else {
                age = 999_999
            }
        }

        return MeisterLastSnapshot(
            ts: tsDate,
            score: score,
            err: err,
            warn: warn,
            twin: twin,
            version: version,
            profile: profile,
            ageSeconds: age
        )
    }

    static func preferredMaintainCLI(preferredTwinPath: URL) -> String {
        if let raw = try? String(contentsOf: preferredTwinPath, encoding: .utf8) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "meister" || t == "meisterSiri" { return t }
        }
        // Default: Apple twin (keep-current LaunchAgents)
        if ShellRunner.findExecutable("meisterSiri") != nil { return "meisterSiri" }
        return "meister"
    }

    /// Snapshot for `heald doctor` / debug status.
    static func writeHealdView(snap: MeisterLastSnapshot?, preferred: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("meister_bridge.json")
        var dict: [String: Any] = [
            "schema": "heald.meister_bridge/v1",
            "preferred_maintain": preferred,
            "last_json_present": snap != nil,
            "ts": ISO8601DateFormatter().string(from: Date()),
        ]
        if let snap {
            dict["meister_score"] = snap.score as Any
            dict["meister_err"] = snap.err
            dict["meister_warn"] = snap.warn
            dict["meister_age_sec"] = Int(snap.ageSeconds)
            dict["meister_twin"] = snap.twin as Any
            dict["meister_version"] = snap.version as Any
            dict["meister_profile"] = snap.profile as Any
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: out, options: .atomic)
        }
    }
}
