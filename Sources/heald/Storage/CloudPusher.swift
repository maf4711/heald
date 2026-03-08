import Foundation
import ServiceLifecycle
import OSLog

/// Pushes metrics to the cloud dashboard API (CLOUD-02, CLOUD-04).
/// Buffers locally when the API is unreachable and retries on reconnection.
struct CloudPusher: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    private static let pushInterval: Duration = .seconds(10)
    private static let maxBufferSize = 100

    // Configuration from environment or defaults
    private var apiURL: String { ProcessInfo.processInfo.environment["HEALD_API_URL"] ?? "https://heald.merados.com/api/ingest" }
    private var apiKey: String { ProcessInfo.processInfo.environment["HEALD_API_KEY"] ?? "" }
    private var machineId: String { ProcessInfo.processInfo.environment["HEALD_MACHINE_ID"] ?? machineName() }

    func run() async throws {
        guard !apiKey.isEmpty else {
            Logger.storage.info("CloudPusher: No HEALD_API_KEY set — cloud push disabled")
            // Keep running but do nothing
            while true { try await Task.sleep(for: .seconds(3600)) }
        }

        var eventBuffer: [[String: Any]] = []

        while true {
            try await Task.sleep(for: Self.pushInterval)

            let payload = await buildPayload()

            do {
                try await pushToCloud(payload: payload, buffer: &eventBuffer)
                Logger.storage.debug("CloudPusher: push OK")
            } catch {
                // CLOUD-04: buffer on failure
                if let events = payload["events"] as? [[String: Any]] {
                    eventBuffer.append(contentsOf: events)
                    if eventBuffer.count > Self.maxBufferSize {
                        eventBuffer.removeFirst(eventBuffer.count - Self.maxBufferSize)
                    }
                }
                Logger.storage.warning("CloudPusher: push failed, buffered (\(eventBuffer.count) events) — \(error)")
            }
        }
    }

    private func buildPayload() async -> [String: Any] {
        let cpu = await store.cpu
        let ram = await store.ram
        let disk = await store.disk
        let processes = await store.processes
        let network = await store.network
        let battery = await store.battery
        let uptime = await store.uptime
        let thermal = await store.thermal
        let benchmark = await store.benchmark

        // Decompose into named sub-dicts to avoid Swift type-checker timeout
        let cpuDict: [String: Any] = [
            "overall": cpu.overall,
            "perCore": cpu.perCore,
        ]

        let ramDict: [String: Any] = [
            "usedGB": round(ram.used / 1_073_741_824 * 100) / 100,
            "wiredGB": round(ram.wired / 1_073_741_824 * 100) / 100,
            "compressedGB": round(ram.compressed / 1_073_741_824 * 100) / 100,
            "swapUsedMB": round(ram.swapUsed / 1_048_576 * 100) / 100,
            "pressureLevel": ram.pressureLevel,
        ]

        let volumesList: [[String: Any]] = disk.volumes.map { vol in
            ["name": vol.volumeName, "mountPoint": vol.mountPoint,
             "totalGB": round(Double(vol.totalBytes) / 1_073_741_824 * 100) / 100,
             "freeGB": round(Double(vol.freeBytes) / 1_073_741_824 * 100) / 100] as [String: Any]
        }
        let smartList = disk.smart.map { ["bsdName": $0.bsdName, "status": $0.status] }
        let diskDict: [String: Any] = ["volumes": volumesList, "smart": smartList]

        let processDict: [String: Any] = [
            "topCPU": processes.byCPU.prefix(5).map { processEntryDict($0) },
            "topRAM": processes.byRAM.prefix(5).map { processEntryDict($0) },
        ]

        let networkDict: [String: Any] = [
            "interface": network.interfaceName,
            "rxBytesPerSec": round(network.rxBytesPerSec),
            "txBytesPerSec": round(network.txBytesPerSec),
            "latencyMs": network.latencyMs as Any,
            "packetLossPercent": network.packetLossPercent as Any,
        ]

        var batteryDict: [String: Any]? = nil
        if battery.isPresent {
            batteryDict = [
                "cycleCount": battery.cycleCount,
                "maxCapacityPercent": battery.maxCapacityPercent,
                "currentCharge": battery.currentCharge,
                "isCharging": battery.isCharging,
                "condition": battery.condition,
                "temperature": battery.temperature as Any,
            ]
        }

        let uptimeDict: [String: Any] = [
            "systemSeconds": Int(uptime.systemUptimeSeconds),
            "daemonSeconds": Int(uptime.daemonUptimeSeconds),
            "systemFormatted": uptime.systemUptimeFormatted,
        ]

        var benchmarkDict: [String: Any]? = nil
        if benchmark.timestamp != Date.distantPast {
            benchmarkDict = [
                "cpuSingleCore": round(benchmark.cpuSingleCore),
                "cpuMultiCore": round(benchmark.cpuMultiCore),
                "diskWriteMBs": round(benchmark.diskWriteMBs),
                "diskReadMBs": round(benchmark.diskReadMBs),
                "memoryBandwidthGBs": round(benchmark.memoryBandwidthGBs * 10) / 10,
                "overallScore": benchmark.overallScore,
                "coreCount": benchmark.coreCount,
                "timestamp": ISO8601DateFormatter().string(from: benchmark.timestamp),
            ]
        }

        var metrics: [String: Any] = [
            "machineId": machineId,
            "hostname": Host.current().localizedName ?? machineName(),
            "cpu": cpuDict,
            "ram": ramDict,
            "disk": diskDict,
            "processes": processDict,
            "network": networkDict,
            "uptime": uptimeDict,
            "thermal": thermal.thermalState.rawValue,
        ]
        if let batteryDict { metrics["battery"] = batteryDict }
        if let benchmarkDict { metrics["benchmark"] = benchmarkDict }

        return ["metrics": metrics, "events": [] as [[String: Any]]]
    }

    private func pushToCloud(payload: [String: Any], buffer: inout [[String: Any]]) async throws {
        var fullPayload = payload

        // Flush buffer if we have buffered events
        if !buffer.isEmpty {
            var events = (fullPayload["events"] as? [[String: Any]]) ?? []
            events.append(contentsOf: buffer)
            fullPayload["events"] = events
        }

        let data = try JSONSerialization.data(withJSONObject: fullPayload)
        var request = URLRequest(url: URL(string: apiURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = data
        request.timeoutInterval = 10

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CloudError.pushFailed(statusCode: code)
        }

        // Success — clear buffer
        buffer.removeAll()
    }

    private func processEntryDict(_ p: ProcessEntry) -> [String: Any] {
        ["pid": p.pid, "name": p.name, "cpuPercent": p.cpuPercent,
         "ramMB": round(Double(p.ramBytes) / 1_048_576 * 10) / 10, "system": p.isSystem]
    }
}

private enum CloudError: Error {
    case pushFailed(statusCode: Int)
}

private func machineName() -> String {
    Host.current().localizedName ?? ProcessInfo.processInfo.hostName
}
