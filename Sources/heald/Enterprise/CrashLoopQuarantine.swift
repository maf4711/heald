import Foundation
import OSLog

/// Detect apps that crash/restart repeatedly; quarantine user LaunchAgents that relaunch them.
actor CrashLoopQuarantine {
    private let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".heald/data/crash_loop.json")

    struct State: Codable {
        var crashes: [String: [TimeInterval]] = [:]
    }

    func recordMissing(app: String, policy: PolicyPack, activityLog: ActivityLog) async {
        guard policy.crashLoopQuarantine else { return }
        var state = load()
        let now = Date().timeIntervalSince1970
        var list = state.crashes[app] ?? []
        list.append(now)
        let window = TimeInterval(policy.crashLoopWindowSec)
        list = list.filter { now - $0 <= window }
        state.crashes[app] = list
        let count = list.count
        save(state)

        guard count >= policy.crashLoopCount else { return }

        Logger.health.error("Crash loop: \(app) x\(count) in \(policy.crashLoopWindowSec)s")
        try? await activityLog.log(event: ActivityEvent(
            type: .crashDetected,
            summary: "Crash loop: \(app) (\(count)x) — quarantine LaunchAgents",
            detail: "window=\(policy.crashLoopWindowSec)s"
        ))
        if policy.allowsRemediation() {
            quarantineAgents(matching: app)
        }
        state.crashes[app] = []
        save(state)

        NotificationService.sendNotification(
            title: "heald crash-loop",
            message: "\(app) crashed \(policy.crashLoopCount)× — agents quarantined"
        )
        await WebhookNotifier.shared.emit(
            title: "Crash loop",
            text: "\(app) quarantined after \(policy.crashLoopCount) crashes",
            severity: "critical"
        )
        await FleetAck.record(action: "crash_loop_quarantine", result: "ok", detail: app)
    }

    private func quarantineAgents(matching app: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }

        let needle = app.lowercased()
        for plist in items where plist.pathExtension == "plist" {
            let content = (try? String(contentsOf: plist, encoding: .utf8)) ?? ""
            if content.lowercased().contains(needle) {
                _ = ShellRunner.run("/bin/launchctl", arguments: ["unload", plist.path])
                let dest = plist.appendingPathExtension("crashloop.\(Int(Date().timeIntervalSince1970))")
                try? FileManager.default.moveItem(at: plist, to: dest)
                Logger.health.warning("Quarantined agent for crash-loop: \(plist.lastPathComponent)")
            }
        }
    }

    private func load() -> State {
        guard let data = try? Data(contentsOf: stateURL),
              let s = try? JSONDecoder().decode(State.self, from: data) else {
            return State()
        }
        return s
    }

    private func save(_ state: State) {
        try? FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }
}
