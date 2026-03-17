import Foundation
import GRDB
import OSLog

/// SQLite ring-buffer for metric snapshots (LOG-02, LOG-03).
/// Stores time-series data with automatic retention management.
actor MetricsDatabase {
    private let dbQueue: DatabaseQueue
    private let retentionDays: Int

    init(path: String, retentionDays: Int = 7) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            db.trace { Logger.storage.debug("SQL: \($0)") }
        }

        // Create parent directory if needed
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        dbQueue = try DatabaseQueue(path: path, configuration: config)
        self.retentionDays = retentionDays

        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS cpu_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    overall REAL NOT NULL,
                    per_core TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS ram_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    used REAL NOT NULL,
                    wired REAL NOT NULL,
                    active REAL NOT NULL,
                    compressed REAL NOT NULL,
                    swap_used REAL NOT NULL,
                    swap_total REAL NOT NULL,
                    pressure_level INTEGER NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS disk_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    volumes TEXT NOT NULL,
                    io TEXT NOT NULL,
                    smart TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS process_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    by_cpu TEXT NOT NULL,
                    by_ram TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS benchmark_results (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    cpu_single_core REAL NOT NULL,
                    cpu_multi_core REAL NOT NULL,
                    disk_write_mbs REAL NOT NULL,
                    disk_read_mbs REAL NOT NULL,
                    memory_bandwidth_gbs REAL NOT NULL,
                    duration_seconds REAL NOT NULL,
                    core_count INTEGER NOT NULL,
                    overall_score INTEGER NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS network_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    interface TEXT NOT NULL,
                    rx_bytes_per_sec REAL NOT NULL,
                    tx_bytes_per_sec REAL NOT NULL,
                    latency_ms REAL,
                    packet_loss_percent REAL
                )
                """)

            // Indices for time-range queries and retention cleanup
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_cpu_ts ON cpu_metrics(timestamp)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_ram_ts ON ram_metrics(timestamp)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_disk_ts ON disk_metrics(timestamp)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_proc_ts ON process_metrics(timestamp)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_bench_ts ON benchmark_results(timestamp)")
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_net_ts ON network_metrics(timestamp)")

            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS icloud_metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    is_enabled INTEGER NOT NULL,
                    optimize_storage INTEGER NOT NULL,
                    local_files INTEGER NOT NULL,
                    cloud_files INTEGER NOT NULL,
                    sync_percent REAL NOT NULL,
                    directories INTEGER NOT NULL,
                    evicted_dirs TEXT NOT NULL,
                    conflicts INTEGER NOT NULL,
                    docs_size INTEGER NOT NULL,
                    disk_free INTEGER NOT NULL,
                    bird_running INTEGER NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX IF NOT EXISTS idx_icloud_ts ON icloud_metrics(timestamp)")
        }

        Logger.storage.info("MetricsDatabase opened at \(path)")
    }

    // MARK: - Insert

    func insertCPU(_ snapshot: CPUSnapshot) throws {
        let ts = ISO8601DateFormatter().string(from: snapshot.timestamp)
        let coreJSON = try String(data: JSONSerialization.data(withJSONObject: snapshot.perCore), encoding: .utf8) ?? "[]"

        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO cpu_metrics (timestamp, overall, per_core) VALUES (?, ?, ?)",
                arguments: [ts, snapshot.overall, coreJSON]
            )
        }
    }

    func insertRAM(_ snapshot: RAMSnapshot) throws {
        let ts = ISO8601DateFormatter().string(from: snapshot.timestamp)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO ram_metrics (timestamp, used, wired, active, compressed, swap_used, swap_total, pressure_level)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [ts, snapshot.used, snapshot.wired, snapshot.active, snapshot.compressed,
                           snapshot.swapUsed, snapshot.swapTotal, snapshot.pressureLevel]
            )
        }
    }

    func insertDisk(_ snapshot: DiskSnapshot) throws {
        let ts = ISO8601DateFormatter().string(from: snapshot.timestamp)
        let encoder = JSONEncoder()

        let volumesData = try encoder.encode(snapshot.volumes.map { CodableVolume(from: $0) })
        let ioData = try encoder.encode(snapshot.io.map { CodableIO(from: $0) })
        let smartData = try encoder.encode(snapshot.smart.map { CodableSMART(from: $0) })

        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO disk_metrics (timestamp, volumes, io, smart) VALUES (?, ?, ?, ?)",
                arguments: [ts, String(data: volumesData, encoding: .utf8)!,
                           String(data: ioData, encoding: .utf8)!,
                           String(data: smartData, encoding: .utf8)!]
            )
        }
    }

    func insertProcesses(_ snapshot: ProcessSnapshot) throws {
        let ts = ISO8601DateFormatter().string(from: snapshot.timestamp)
        let encoder = JSONEncoder()

        let cpuData = try encoder.encode(snapshot.byCPU.map { CodableProcess(from: $0) })
        let ramData = try encoder.encode(snapshot.byRAM.map { CodableProcess(from: $0) })

        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO process_metrics (timestamp, by_cpu, by_ram) VALUES (?, ?, ?)",
                arguments: [ts, String(data: cpuData, encoding: .utf8)!,
                           String(data: ramData, encoding: .utf8)!]
            )
        }
    }

    // MARK: - Benchmark

    func insertBenchmark(_ snapshot: BenchmarkSnapshot) throws {
        let ts = ISO8601DateFormatter().string(from: snapshot.timestamp)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO benchmark_results
                    (timestamp, cpu_single_core, cpu_multi_core, disk_write_mbs, disk_read_mbs,
                     memory_bandwidth_gbs, duration_seconds, core_count, overall_score)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [ts, snapshot.cpuSingleCore, snapshot.cpuMultiCore,
                           snapshot.diskWriteMBs, snapshot.diskReadMBs,
                           snapshot.memoryBandwidthGBs, snapshot.durationSeconds,
                           snapshot.coreCount, snapshot.overallScore]
            )
        }
    }

    func recentBenchmarks(limit: Int = 30) throws -> [[String: Any]] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM benchmark_results ORDER BY timestamp DESC LIMIT ?",
                arguments: [limit])
            return rows.map { row in
                [
                    "timestamp": row["timestamp"] as String,
                    "cpuSingleCore": row["cpu_single_core"] as Double,
                    "cpuMultiCore": row["cpu_multi_core"] as Double,
                    "diskWriteMBs": row["disk_write_mbs"] as Double,
                    "diskReadMBs": row["disk_read_mbs"] as Double,
                    "memoryBandwidthGBs": row["memory_bandwidth_gbs"] as Double,
                    "durationSeconds": row["duration_seconds"] as Double,
                    "coreCount": row["core_count"] as Int,
                    "overallScore": row["overall_score"] as Int,
                ]
            }
        }
    }

    // MARK: - Network

    func insertNetwork(_ snapshot: NetworkSnapshot) throws {
        let ts = ISO8601DateFormatter().string(from: snapshot.timestamp)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO network_metrics
                    (timestamp, interface, rx_bytes_per_sec, tx_bytes_per_sec, latency_ms, packet_loss_percent)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: StatementArguments([
                    ts as DatabaseValueConvertible,
                    snapshot.interfaceName as DatabaseValueConvertible,
                    snapshot.rxBytesPerSec as DatabaseValueConvertible,
                    snapshot.txBytesPerSec as DatabaseValueConvertible,
                    snapshot.latencyMs as DatabaseValueConvertible?,
                    snapshot.packetLossPercent as DatabaseValueConvertible?,
                ])!
            )
        }
    }

    // MARK: - iCloud

    func insertICloud(_ snapshot: ICloudSnapshot) throws {
        let ts = ISO8601DateFormatter().string(from: snapshot.timestamp)
        let encoder = JSONEncoder()
        let evictedJSON = (try? String(data: encoder.encode(snapshot.evictedDirs), encoding: .utf8)) ?? "[]"

        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO icloud_metrics
                    (timestamp, is_enabled, optimize_storage, local_files, cloud_files,
                     sync_percent, directories, evicted_dirs, conflicts, docs_size, disk_free, bird_running)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [ts, snapshot.isEnabled ? 1 : 0, snapshot.optimizeStorage ? 1 : 0,
                           snapshot.localFiles, snapshot.cloudFiles,
                           snapshot.syncPercent, snapshot.directories,
                           evictedJSON, snapshot.conflicts,
                           snapshot.docsSize, snapshot.diskFree,
                           snapshot.birdRunning ? 1 : 0]
            )
        }
    }

    // MARK: - Retention (LOG-03)

    func purgeOldRecords() throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date())!
        let cutoffStr = ISO8601DateFormatter().string(from: cutoff)

        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM cpu_metrics WHERE timestamp < ?", arguments: [cutoffStr])
            try db.execute(sql: "DELETE FROM ram_metrics WHERE timestamp < ?", arguments: [cutoffStr])
            try db.execute(sql: "DELETE FROM disk_metrics WHERE timestamp < ?", arguments: [cutoffStr])
            try db.execute(sql: "DELETE FROM process_metrics WHERE timestamp < ?", arguments: [cutoffStr])
            try db.execute(sql: "DELETE FROM network_metrics WHERE timestamp < ?", arguments: [cutoffStr])
            try db.execute(sql: "DELETE FROM icloud_metrics WHERE timestamp < ?", arguments: [cutoffStr])
            // Keep benchmark results for 90 days (long-term trend)
            let benchCutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
            let benchCutoffStr = ISO8601DateFormatter().string(from: benchCutoff)
            try db.execute(sql: "DELETE FROM benchmark_results WHERE timestamp < ?", arguments: [benchCutoffStr])
        }

        // Reclaim disk space
        try dbQueue.write { db in
            try db.execute(sql: "PRAGMA incremental_vacuum")
        }

        Logger.storage.info("Purged metrics older than \(self.retentionDays) days")
    }

    // MARK: - Query (for dashboard API push)

    func recentCPU(since: Date) throws -> [[String: Any]] {
        let ts = ISO8601DateFormatter().string(from: since)
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT timestamp, overall, per_core FROM cpu_metrics WHERE timestamp >= ? ORDER BY timestamp",
                arguments: [ts])
            return rows.map { row in
                [
                    "timestamp": row["timestamp"] as String,
                    "overall": row["overall"] as Double,
                    "per_core": row["per_core"] as String,
                ]
            }
        }
    }

    func recentRAM(since: Date) throws -> [[String: Any]] {
        let ts = ISO8601DateFormatter().string(from: since)
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM ram_metrics WHERE timestamp >= ? ORDER BY timestamp",
                arguments: [ts])
            return rows.map { row in
                [
                    "timestamp": row["timestamp"] as String,
                    "used": row["used"] as Double,
                    "wired": row["wired"] as Double,
                    "compressed": row["compressed"] as Double,
                    "swap_used": row["swap_used"] as Double,
                    "pressure_level": row["pressure_level"] as Int,
                ]
            }
        }
    }

    func rowCounts() throws -> [String: Int] {
        try dbQueue.read { db in
            let cpu = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM cpu_metrics") ?? 0
            let ram = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM ram_metrics") ?? 0
            let disk = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM disk_metrics") ?? 0
            let proc = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM process_metrics") ?? 0
            return ["cpu": cpu, "ram": ram, "disk": disk, "processes": proc]
        }
    }
}

// MARK: - Codable helpers for JSON columns

private struct CodableVolume: Codable {
    let mountPoint: String
    let volumeName: String
    let totalBytes: Int64
    let freeBytes: Int64

    init(from v: VolumeSpaceInfo) {
        mountPoint = v.mountPoint; volumeName = v.volumeName
        totalBytes = v.totalBytes; freeBytes = v.freeBytes
    }
}

private struct CodableIO: Codable {
    let readBytes: Int64
    let writeBytes: Int64
    let interval: TimeInterval

    init(from d: DiskIODelta) {
        readBytes = d.readBytes; writeBytes = d.writeBytes; interval = d.interval
    }
}

private struct CodableSMART: Codable {
    let bsdName: String
    let status: String
    let temperature: Int?
    let percentageUsed: Int?

    init(from s: SMARTInfo) {
        bsdName = s.bsdName; status = s.status
        temperature = s.temperature; percentageUsed = s.percentageUsed
    }
}

private struct CodableProcess: Codable {
    let pid: Int32
    let name: String
    let cpuPercent: Double
    let ramBytes: Int64
    let isSystem: Bool

    init(from p: ProcessEntry) {
        pid = p.pid; name = p.name; cpuPercent = p.cpuPercent
        ramBytes = p.ramBytes; isSystem = p.isSystem
    }
}
