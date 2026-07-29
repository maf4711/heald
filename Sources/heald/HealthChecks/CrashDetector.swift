import Foundation
import OSLog

/// HEAL-04: Detects crashed critical apps and restarts them + crash-loop quarantine.
struct CrashDetector {
    /// Apps to watch for crashes (configurable).
    static let watchList: [String] = [
        "Finder", "Dock", "SystemUIServer",
    ]

    private let crashLoop = CrashLoopQuarantine()

    /// Check if watched apps are running, restart if missing.
    func check(activityLog: ActivityLog) async -> [String] {
        var restarted: [String] = []
        let policy = await PolicyStore.shared.current()

        for appName in Self.watchList {
            if !isRunning(appName) {
                Logger.health.warning("Crash detected: \(appName) not running")
                await crashLoop.recordMissing(app: appName, policy: policy, activityLog: activityLog)

                let success = policy.allowsRemediation() ? restartApp(appName) : false
                let event = ActivityEvent(
                    type: success ? .processRestarted : .crashDetected,
                    summary: success ? "Restarted \(appName)" : "Detected crash: \(appName)",
                    beforeState: "\(appName) not running",
                    afterState: success ? "\(appName) restarted" : "\(appName) still not running"
                )
                try? await activityLog.log(event: event)

                if success { restarted.append(appName) }
            }
        }

        return restarted
    }

    private func isRunning(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", name]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func restartApp(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", name]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            Logger.health.error("Failed to restart \(name): \(error)")
            return false
        }
    }
}
