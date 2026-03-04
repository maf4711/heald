import Foundation
import Darwin
import OSLog

/// HEAL-01, HEAL-02: Kills sustained high-CPU processes using SIGTERM→SIGKILL sequence.
struct ProcessHealer {
    /// Tracks how long a process has been above threshold.
    /// Key: pid, Value: first-seen timestamp.
    private var offenders: [Int32: Date] = [:]

    private let cpuThreshold: Double = 90.0      // HEAL-01: >90% CPU
    private let sustainedSeconds: TimeInterval = 300  // 5 minutes sustained
    private let killGracePeriod: TimeInterval = 10    // HEAL-02: wait 10s after SIGTERM before SIGKILL

    /// Evaluate current process snapshot and kill sustained offenders.
    /// Returns list of actions taken (for audit log).
    mutating func evaluate(processes: ProcessSnapshot, activityLog: ActivityLog) async -> [HealAction] {
        var actions: [HealAction] = []
        let now = Date()

        // Track currently offending processes
        var currentOffenders = Set<Int32>()

        for proc in processes.byCPU {
            guard proc.cpuPercent >= cpuThreshold else { continue }
            guard !ProcessSafelist.isProtected(name: proc.name, uid: proc.uid) else { continue }

            currentOffenders.insert(proc.pid)

            if let firstSeen = offenders[proc.pid] {
                let duration = now.timeIntervalSince(firstSeen)
                if duration >= sustainedSeconds {
                    // Kill it
                    let action = await killProcess(proc, activityLog: activityLog)
                    actions.append(action)
                    offenders.removeValue(forKey: proc.pid)
                }
            } else {
                // First time seeing this offender
                offenders[proc.pid] = now
                Logger.healer.debug("Tracking offender: \(proc.name) (pid=\(proc.pid)) at \(proc.cpuPercent)% CPU")
            }
        }

        // Remove processes that are no longer offending
        offenders = offenders.filter { currentOffenders.contains($0.key) }

        return actions
    }

    /// HEAL-02: SIGTERM first, SIGKILL as fallback after grace period.
    private func killProcess(_ proc: ProcessEntry, activityLog: ActivityLog) async -> HealAction {
        let beforeState = "pid=\(proc.pid) name=\(proc.name) cpu=\(proc.cpuPercent)%"

        Logger.healer.warning("Killing \(proc.name) (pid=\(proc.pid)) — sustained >\(self.cpuThreshold)% CPU for >\(self.sustainedSeconds)s")

        // Step 1: SIGTERM
        kill(proc.pid, SIGTERM)

        // Wait grace period
        try? await Task.sleep(for: .seconds(killGracePeriod))

        // Step 2: Check if still alive, SIGKILL if needed
        let stillAlive = kill(proc.pid, 0) == 0
        if stillAlive {
            Logger.healer.warning("SIGTERM failed for \(proc.name) — sending SIGKILL")
            kill(proc.pid, SIGKILL)
        }

        let method = stillAlive ? "SIGKILL" : "SIGTERM"
        let afterState = "terminated via \(method)"

        // Log to activity log
        try? await activityLog.log(event: ActivityEvent(
            type: .processKilled,
            summary: "Killed \(proc.name) (pid \(proc.pid)) — \(method)",
            detail: "Sustained \(proc.cpuPercent)% CPU",
            beforeState: beforeState,
            afterState: afterState
        ))

        return HealAction(processName: proc.name, pid: proc.pid, method: method)
    }
}

struct HealAction: Sendable {
    let processName: String
    let pid: Int32
    let method: String
}
