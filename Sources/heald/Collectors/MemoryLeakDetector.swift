import Foundation
import ServiceLifecycle
import OSLog

/// Tracks process memory over time to detect leaks.
/// A process is flagged as a suspect if it grows continuously for 30+ minutes
/// without ever decreasing, and exceeds a minimum growth rate.
struct MemoryLeakDetector: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    /// Minimum tracking window before flagging (30 minutes)
    private let minTrackingMinutes: Double = 30
    /// Minimum growth rate to flag (10 MB/hour)
    private let minGrowthRateMBPerHour: Double = 10
    /// Minimum absolute size to care about (100 MB)
    private let minSizeMB: Double = 100

    func run() async throws {
        Logger.collector.info("MemoryLeakDetector started")

        // pid -> (firstSeen, firstMB, lastMB, everDecreased)
        var tracking: [Int32: (firstSeen: Date, firstMB: Double, lastMB: Double, everDecreased: Bool)] = [:]

        while true {
            try await Task.sleep(for: .seconds(60))

            let processes = await store.processes
            guard processes.timestamp != .distantPast else { continue }

            let now = Date()
            var currentPids = Set<Int32>()

            // Update tracking for all processes
            for entry in processes.byRAM {
                let mb = Double(entry.ramBytes) / 1_048_576
                currentPids.insert(entry.pid)

                if var record = tracking[entry.pid] {
                    let decreased = mb < record.lastMB
                    record.everDecreased = record.everDecreased || decreased
                    record.lastMB = mb
                    tracking[entry.pid] = record
                } else {
                    tracking[entry.pid] = (firstSeen: now, firstMB: mb, lastMB: mb, everDecreased: false)
                }
            }

            // Prune exited processes
            for pid in tracking.keys where !currentPids.contains(pid) {
                tracking.removeValue(forKey: pid)
            }

            // Evaluate suspects
            var suspects: [MemoryLeakSuspect] = []

            for entry in processes.byRAM {
                guard let record = tracking[entry.pid] else { continue }
                guard !record.everDecreased else { continue }

                let trackingMinutes = now.timeIntervalSince(record.firstSeen) / 60
                guard trackingMinutes >= minTrackingMinutes else { continue }

                let growthMB = record.lastMB - record.firstMB
                guard growthMB > 0 else { continue }

                let growthRate = growthMB / (trackingMinutes / 60)
                guard growthRate >= minGrowthRateMBPerHour else { continue }
                guard record.lastMB >= minSizeMB else { continue }

                suspects.append(MemoryLeakSuspect(
                    pid: entry.pid,
                    name: entry.name,
                    currentMB: record.lastMB,
                    growthMB: growthMB,
                    trackingMinutes: trackingMinutes,
                    growthRateMBPerHour: growthRate
                ))
            }

            suspects.sort { $0.growthRateMBPerHour > $1.growthRateMBPerHour }

            let snapshot = MemoryLeakSnapshot(suspects: suspects, timestamp: now)
            await store.updateMemoryLeak(snapshot)

            for suspect in suspects {
                Logger.collector.warning(
                    "Memory leak suspect: \(suspect.name) (PID \(suspect.pid)) — \(Int(suspect.currentMB))MB, growing \(Int(suspect.growthRateMBPerHour))MB/h for \(Int(suspect.trackingMinutes))min"
                )
                try? await activityLog.log(event: ActivityEvent(
                    type: .memoryLeakDetected,
                    summary: "\(suspect.name) growing \(Int(suspect.growthRateMBPerHour))MB/h",
                    detail: "PID \(suspect.pid), current \(Int(suspect.currentMB))MB, +\(Int(suspect.growthMB))MB over \(Int(suspect.trackingMinutes))min"
                ))
            }
        }
    }
}
