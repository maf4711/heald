import Foundation
import ServiceLifecycle
import OSLog

struct DebugStatusWriter: Service {
    let store: MetricsStore

    func run() async throws {
        while true {
            try await Task.sleep(for: .seconds(5))
            try await writeStatus()
        }
    }

    private func writeStatus() async throws {
        let cpu = await store.cpu
        let ram = await store.ram
        let disk = await store.disk
        let processes = await store.processes

        let cpuDict: [String: Any] = [
            "overall_percent": round(cpu.overall * 1000) / 10,
            "core_count": cpu.perCore.count,
            "per_core_percent": cpu.perCore.map { round($0 * 1000) / 10 }
        ]

        let ramDict: [String: Any] = [
            "used_gb": round(ram.used / 1_073_741_824 * 100) / 100,
            "wired_gb": round(ram.wired / 1_073_741_824 * 100) / 100,
            "compressed_gb": round(ram.compressed / 1_073_741_824 * 100) / 100,
            "swap_used_mb": round(ram.swapUsed / 1_048_576 * 100) / 100,
            "swap_total_mb": round(ram.swapTotal / 1_048_576 * 100) / 100,
            "pressure_level": ram.pressureLevel
        ]

        let volumesList: [[String: Any]] = disk.volumes.map { vol in
            [
                "name": vol.volumeName,
                "mount_point": vol.mountPoint,
                "total_gb": round(Double(vol.totalBytes) / 1_073_741_824 * 100) / 100,
                "free_gb": round(Double(vol.freeBytes) / 1_073_741_824 * 100) / 100
            ]
        }

        let smartList: [[String: Any]] = disk.smart.map { s in
            [
                "bsd_name": s.bsdName,
                "status": s.status,
                "temperature_c": s.temperature as Any,
                "percentage_used": s.percentageUsed as Any
            ]
        }

        let diskDict: [String: Any] = [
            "volumes": volumesList,
            "smart": smartList
        ]

        let topCPU: [[String: Any]] = processes.byCPU.prefix(5).map { p in
            [
                "pid": p.pid,
                "name": p.name,
                "cpu_percent": p.cpuPercent,
                "ram_mb": round(Double(p.ramBytes) / 1_048_576 * 10) / 10,
                "system": p.isSystem
            ]
        }

        let topRAM: [[String: Any]] = processes.byRAM.prefix(5).map { p in
            [
                "pid": p.pid,
                "name": p.name,
                "cpu_percent": p.cpuPercent,
                "ram_mb": round(Double(p.ramBytes) / 1_048_576 * 10) / 10,
                "system": p.isSystem
            ]
        }

        let processesDict: [String: Any] = [
            "top_cpu": topCPU,
            "top_ram": topRAM
        ]

        let status: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "cpu": cpuDict,
            "ram": ramDict,
            "disk": diskDict,
            "processes": processesDict
        ]

        let data = try JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: "/tmp/heald-status.json"), options: .atomic)
        Logger.collector.info("DebugStatusWriter: wrote /tmp/heald-status.json")
    }
}
