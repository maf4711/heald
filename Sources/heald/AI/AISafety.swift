import Foundation
import HealdCore
import OSLog

// MARK: - Self-Healing Runner

/// Generic retry wrapper. On failure Apple Intelligence may add a short diagnosis to the
/// activity log — it is **advice only**: no model output is ever executed. The runner
/// simply retries the same operation.
struct SelfHealingRunner {
    let ai: AppleIntelligenceClient
    let activityLog: ActivityLog
    let maxRetries: Int = 2

    /// Run an operation; on failure log an advisor diagnosis (if available) and retry it.
    func runSafe(name: String, _ operation: @Sendable () async throws -> Void) async {
        for attempt in 1...(maxRetries + 1) {
            do {
                try await operation()

                if attempt > 1 {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .selfHealed,
                        summary: "\(name) succeeded after \(attempt) attempts"
                    ))
                    Logger.maintenance.info("\(name) self-healed after \(attempt) attempts")
                }
                return

            } catch {
                Logger.maintenance.error("\(name) failed (attempt \(attempt)/\(maxRetries + 1)): \(error)")

                if attempt > maxRetries {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .healingFailed,
                        summary: "\(name) failed after \(maxRetries + 1) attempts",
                        detail: error.localizedDescription
                    ))
                    break
                }

                if attempt == 1 {
                    await logDiagnosis(name: name, error: error.localizedDescription)
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    /// Ask the on-device advisor *why* it failed and log the answer. Never executed.
    private func logDiagnosis(name: String, error: String) async {
        guard await ai.isAvailable else { return }
        let ai = self.ai
        let result = await AutohealAdvisor.withDeadline(AutohealAdvisor.defaultTimeout) {
            await ai.diagnoseFailure(moduleName: name, error: error)
        }
        guard case .value(let text?) = result else { return }
        try? await activityLog.log(event: ActivityEvent(
            type: .aiDiagnosis,
            summary: "Advisor diagnosis for \(name)",
            detail: String(text.prefix(AutohealAdvisor.maxRationaleChars)),
            aiGenerated: true
        ))
    }
}
