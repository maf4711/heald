import Foundation
import HealdCore

extension SelfHealOrchestrator {
    /// Drain scanner-requested `app_restart` / `dns_flush` and run them via `fire`
    /// (advisor + cooldown + consent: consent=log logs BLOCKED and never executes).
    func healScannerFindings(
        state: HealCooldownState,
        policy: PolicyPack,
        memoryCritical: Bool,
        budget: inout AdvisorBudget
    ) async {
        for healAction in [HealdCore.HealAction.appRestart, .dnsFlush] {
            let key = healAction.rawValue
            let targets = await FindingsStore.shared.peek(healAction)
            guard !targets.isEmpty else { continue }
            let reason = "\(key) for \(targets.joined(separator: ", "))"
            // Drain inside the action: requests survive cooldown, advisor defer and consent=ask.
            let outcome = await fire(state: state, key: key, reason: reason, policy: policy, memoryCritical: memoryCritical, budget: &budget) {
                let requests = await FindingsStore.shared.drain(healAction)
                await self.scannerRemediation.run(healAction, requests, activityLog: self.activityLog)
            }
            switch (ScannerQueue.disposition(after: outcome), outcome) {
            case (.drop, _):
                _ = await FindingsStore.shared.drain(healAction) // consent=log / advisor skip: never runs
            case (.keep, .blockedAsk):
                // Keep waiting for `heald approve`, but don't re-notify every 60 s cooldown.
                let mark = Date().addingTimeInterval(ScannerQueue.askRetryInterval - cooldown(for: key))
                await state.markFired(key: key, at: mark)
            default:
                break
            }
        }
    }
}
