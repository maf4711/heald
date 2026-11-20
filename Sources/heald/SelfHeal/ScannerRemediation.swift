import Foundation
import HealdCore
import OSLog

/// Executes scanner-requested fixes. Only ever called from inside `SelfHealOrchestrator.fire`,
/// i.e. after the advisor, cooldown and consent gate (consent=log never reaches this code).
struct ScannerRemediation {
    /// True when every request was remediated.
    func run(_ action: HealdCore.HealAction, _ requests: [RemediationRequest], activityLog: ActivityLog) async -> Bool {
        switch action {
        case .appRestart:
            var ok = true
            for r in requests where !(await relaunch(r, activityLog: activityLog)) { ok = false }
            return ok
        case .dnsFlush:
            return await flushDNS(requests, activityLog: activityLog)
        default:
            Logger.healer.error("ScannerRemediation: unsupported action \(action.rawValue)")
            return false
        }
    }

    private func relaunch(_ r: RemediationRequest, activityLog: ActivityLog) async -> Bool {
        let app = r.target
        guard DiagnosisEngine.restartableApps.contains(app) else { return false }
        // Already back (launchd relaunched it) counts as healed; otherwise open it.
        let ok = isRunning(app)
            || ShellRunner.run("/usr/bin/open", arguments: ["-a", app], timeoutSeconds: 10).succeeded
        try? await activityLog.log(event: ActivityEvent(
            type: ok ? .processRestarted : .healingFailed,
            summary: ok ? "Restarted \(app) after crash" : "Failed to restart \(app)",
            detail: r.fingerprints.sorted().joined(separator: ", "),
            beforeState: "\(app) crashed",
            afterState: ok ? "running" : "still down"
        ))
        await FindingsStore.shared.recordHeal(r, succeeded: ok)
        return ok
    }

    private func flushDNS(_ requests: [RemediationRequest], activityLog: ActivityLog) async -> Bool {
        let ok = ShellRunner.run("/usr/bin/dscacheutil", arguments: ["-flushcache"], timeoutSeconds: 5).succeeded
        _ = ShellRunner.run("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"], timeoutSeconds: 3)
        try? await activityLog.log(event: ActivityEvent(
            type: .dnsFlushed,
            summary: "DNS flushed after mDNSResponder faults",
            detail: requests.flatMap(\.fingerprints).sorted().joined(separator: ", ")
        ))
        for r in requests { await FindingsStore.shared.recordHeal(r, succeeded: ok) }
        return ok
    }

    private func isRunning(_ name: String) -> Bool {
        ShellRunner.run("/usr/bin/pgrep", arguments: ["-x", "--", name], timeoutSeconds: 3).succeeded
    }
}
