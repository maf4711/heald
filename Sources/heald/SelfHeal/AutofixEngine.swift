import Foundation
import OSLog

/// Deterministic fixes adapted from meisterSiri autofix — **native**, no external CLI.
struct AutofixEngine: Sendable {
    /// Try to enable Application Firewall (may require existing privileges).
    func enableFirewall(activityLog: ActivityLog) async {
        let fw = "/usr/libexec/ApplicationFirewall/socketfilterfw"
        guard FileManager.default.isExecutableFile(atPath: fw) else {
            Logger.healer.info("Firewall tool missing")
            return
        }
        // Non-interactive; succeeds if already authorized or SIP policy allows
        let r = ShellRunner.run(fw, arguments: ["--setglobalstate", "on"], timeoutSeconds: 8)
        let summary = r.succeeded
            ? "Firewall enabled (or already on)"
            : "Firewall enable failed (needs admin): \(r.errorOutput.prefix(120))"
        try? await activityLog.log(event: ActivityEvent(
            type: r.succeeded ? .selfHealed : .healingFailed,
            summary: summary
        ))
        Logger.healer.info("\(summary)")
    }

    /// Light brew hygiene: cleanup old downloads (no full upgrade — too heavy for hot path).
    func brewCleanupLight(activityLog: ActivityLog) async {
        guard let brew = ShellRunner.findExecutable("brew") else { return }
        let r = ShellRunner.run(brew, arguments: ["cleanup", "-s", "--prune=all"], timeoutSeconds: 60)
        try? await activityLog.log(event: ActivityEvent(
            type: .brewUpgrade,
            summary: r.succeeded ? "brew cleanup light OK" : "brew cleanup failed",
            detail: String((r.output + r.errorOutput).prefix(500))
        ))
    }

    /// Quarantine orphan user LaunchAgents whose Program is missing.
    func quarantineOrphanAgents(activityLog: ActivityLog) async {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }

        var fixed = 0
        for plist in items where plist.pathExtension == "plist" {
            let bin = programPath(from: plist)
            guard let bin, !bin.isEmpty, !FileManager.default.fileExists(atPath: bin) else { continue }

            let label = plist.deletingPathExtension().lastPathComponent
            _ = ShellRunner.run("/bin/launchctl", arguments: ["unload", plist.path], timeoutSeconds: 5)
            let dest = plist.appendingPathExtension("disabled.\(Int(Date().timeIntervalSince1970))")
            do {
                try FileManager.default.moveItem(at: plist, to: dest)
                fixed += 1
                Logger.healer.info("Quarantined orphan agent: \(label) → missing \(bin)")
            } catch {
                Logger.healer.warning("Could not quarantine \(label): \(error.localizedDescription)")
            }
        }
        if fixed > 0 {
            try? await activityLog.log(event: ActivityEvent(
                type: .selfHealed,
                summary: "Quarantined \(fixed) orphan LaunchAgent(s)"
            ))
        }
    }

    private func programPath(from plist: URL) -> String? {
        let r = ShellRunner.run("/usr/bin/plutil", arguments: [
            "-extract", "ProgramArguments.0", "raw", "-o", "-", plist.path,
        ], timeoutSeconds: 5)
        if r.succeeded {
            let s = r.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { return s }
        }
        let r2 = ShellRunner.run("/usr/bin/plutil", arguments: [
            "-extract", "Program", "raw", "-o", "-", plist.path,
        ], timeoutSeconds: 5)
        if r2.succeeded {
            return r2.output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}
