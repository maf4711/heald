import Foundation
import ServiceLifecycle
import OSLog

/// Persists metric snapshots to SQLite and events to NDJSON (LOG-01..04).
/// Runs as a Service alongside collectors, reading from MetricsStore each cycle.
struct StorageService: Service {
    let store: MetricsStore
    let db: MetricsDatabase
    let activityLog: ActivityLog

    func run() async throws {
        // Log daemon start
        try await activityLog.log(event: ActivityEvent(
            type: .daemonStarted,
            summary: "heald daemon started"
        ))

        var retentionCycle = 0

        while true {
            try await Task.sleep(for: .seconds(10))

            // Persist current metrics every 10s (half the collector interval to avoid gaps)
            let cpu = await store.cpu
            let ram = await store.ram
            let disk = await store.disk
            let processes = await store.processes

            do {
                if cpu.timestamp != .distantPast {
                    try await db.insertCPU(cpu)
                }
                if ram.timestamp != .distantPast {
                    try await db.insertRAM(ram)
                }
                if disk.timestamp != .distantPast {
                    try await db.insertDisk(disk)
                }
                if processes.timestamp != .distantPast {
                    try await db.insertProcesses(processes)
                }
            } catch {
                Logger.storage.error("StorageService write failed: \(error)")
            }

            retentionCycle += 1

            // Retention: purge old records every ~1 hour (360 cycles * 10s)
            if retentionCycle % 360 == 0 {
                do {
                    try await db.purgeOldRecords()
                    try await activityLog.rotateIfNeeded()
                    try await activityLog.log(event: ActivityEvent(
                        type: .retentionPurge,
                        summary: "Retention cleanup completed"
                    ))
                } catch {
                    Logger.storage.error("Retention failed: \(error)")
                }
            }
        }
    }
}
