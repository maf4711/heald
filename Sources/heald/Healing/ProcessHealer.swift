import Foundation
import Darwin
import OSLog

/// HEAL-01, HEAL-02: Kills sustained high-CPU processes using SIGTERM→SIGKILL sequence.
/// When Apple Intelligence is available, consults it before kill; WAIT/IGNORE defer or skip.
struct ProcessHealer {
    /// Tracks how long a process has been above threshold.
    /// Key: pid, Value: first-seen timestamp.
    private var offenders: [Int32: Date] = [:]

    private let cpuThreshold: Double = 90.0      // HEAL-01: >90% CPU
    private let sustainedSeconds: TimeInterval = 300  // 5 minutes sustained
    private let killGracePeriod: TimeInterval = 10    // HEAL-02: wait 10s after SIGTERM before SIGKILL

    /// Evaluate current process snapshot and kill sustained offenders.
    mutating func evaluate(
        processes: ProcessSnapshot,
        activityLog: ActivityLog,
        ai: AppleIntelligenceClient
    ) async -> [HealAction] {
        var actions: [HealAction] = []
        let now = Date()

        var currentOffenders = Set<Int32>()

        for proc in processes.byCPU {
            guard proc.cpuPercent >= cpuThreshold else { continue }
            guard !ProcessSafelist.isProtected(name: proc.name, uid: proc.uid) else { continue }

            currentOffenders.insert(proc.pid)

            if let firstSeen = offenders[proc.pid] {
                let duration = now.timeIntervalSince(firstSeen)
                if duration >= sustainedSeconds {
                    let ramMB = Double(proc.ramBytes) / 1_048_576.0
                    let decision = await ai.shouldKillProcess(
                        name: proc.name,
                        cpuPercent: proc.cpuPercent,
                        ramMB: ramMB,
                        duration: duration
                    )

                    switch decision {
                    case .wait:
                        Logger.healer.info("AI WAIT: \(proc.name) pid=\(proc.pid) — extend watch")
                        offenders[proc.pid] = now
                        try? await activityLog.log(event: ActivityEvent(
                            type: .processKilled,
                            summary: "AI deferred kill for \(proc.name) (WAIT)",
                            detail: "cpu=\(proc.cpuPercent)% duration=\(Int(duration))s",
                            aiGenerated: true
                        ))
                        continue
                    case .ignore:
                        Logger.healer.info("AI IGNORE: \(proc.name) pid=\(proc.pid) — stop tracking")
                        offenders.removeValue(forKey: proc.pid)
                        try? await activityLog.log(event: ActivityEvent(
                            type: .processKilled,
                            summary: "AI ignored \(proc.name) (normal load)",
                            detail: "cpu=\(proc.cpuPercent)%",
                            aiGenerated: true
                        ))
                        continue
                    case .kill, .fallbackToRules:
                        let action = await killProcess(
                            proc,
                            activityLog: activityLog,
                            aiGenerated: decision == .kill
                        )
                        actions.append(action)
                        offenders.removeValue(forKey: proc.pid)
                    }
                }
            } else {
                offenders[proc.pid] = now
                Logger.healer.debug("Tracking offender: \(proc.name) (pid=\(proc.pid)) at \(proc.cpuPercent)% CPU")
            }
        }

        offenders = offenders.filter { currentOffenders.contains($0.key) }

        return actions
    }

    /// HEAL-02: SIGTERM first, SIGKILL as fallback after grace period.
    private func killProcess(
        _ proc: ProcessEntry,
        activityLog: ActivityLog,
        aiGenerated: Bool
    ) async -> HealAction {
        let beforeState = "pid=\(proc.pid) name=\(proc.name) cpu=\(proc.cpuPercent)%"

        Logger.healer.warning("Killing \(proc.name) (pid=\(proc.pid)) — sustained >\(self.cpuThreshold)% CPU for >\(self.sustainedSeconds)s")

        kill(proc.pid, SIGTERM)

        try? await Task.sleep(for: .seconds(killGracePeriod))

        let stillAlive = kill(proc.pid, 0) == 0
        if stillAlive {
            Logger.healer.warning("SIGTERM failed for \(proc.name) — sending SIGKILL")
            kill(proc.pid, SIGKILL)
        }

        let method = stillAlive ? "SIGKILL" : "SIGTERM"
        let afterState = "terminated via \(method)"

        try? await activityLog.log(event: ActivityEvent(
            type: .processKilled,
            summary: "Killed \(proc.name) (pid \(proc.pid)) — \(method)",
            detail: "Sustained \(proc.cpuPercent)% CPU",
            beforeState: beforeState,
            afterState: afterState,
            aiGenerated: aiGenerated
        ))

        return HealAction(processName: proc.name, pid: proc.pid, method: method)
    }
}

struct HealAction: Sendable {
    let processName: String
    let pid: Int32
    let method: String
}
