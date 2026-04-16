import Foundation
import OSLog

/// Detects abnormal disk I/O patterns that could indicate SSD wear.
/// Flags processes writing >1GB/min sustained over multiple checks.
struct DiskIOAnomalyDetector {
    /// Threshold: 1 GB/min sustained write rate
    private let writeThresholdBytesPerSec: Double = 1_073_741_824 / 60

    /// Track consecutive anomalies (need 3 in a row to flag)
    private var consecutiveAnomalies = 0
    private var lastHighWriteRate: Double = 0

    mutating func check(store: MetricsStore, activityLog: ActivityLog) async {
        let disk = await store.disk
        guard disk.timestamp != .distantPast else { return }

        // Sum all disk I/O deltas
        var totalWriteBytesPerSec: Double = 0
        for delta in disk.io {
            if delta.interval > 0 {
                totalWriteBytesPerSec += Double(delta.writeBytes) / delta.interval
            }
        }

        if totalWriteBytesPerSec > writeThresholdBytesPerSec {
            consecutiveAnomalies += 1
            lastHighWriteRate = totalWriteBytesPerSec

            // Only flag after 3 consecutive anomalies (15+ seconds of sustained high I/O)
            if consecutiveAnomalies >= 3 {
                let rateMBs = totalWriteBytesPerSec / 1_048_576
                Logger.health.warning("Disk I/O anomaly: \(rateMBs, format: .fixed(precision: 1))MB/s sustained write")

                // Find the likely culprit from top CPU processes (high I/O often correlates)
                let processes = await store.processes
                let suspect = processes.byCPU.first(where: { !$0.isSystem })

                try? await activityLog.log(event: ActivityEvent(
                    type: .diskIOAnomaly,
                    summary: "Sustained high disk write: \(Int(rateMBs))MB/s",
                    detail: suspect.map { "Suspect: \($0.name) (PID \($0.pid), CPU \($0.cpuPercent)%)" }
                ))

                // Reset after logging to avoid spam
                consecutiveAnomalies = 0
            }
        } else {
            consecutiveAnomalies = 0
        }
    }
}
