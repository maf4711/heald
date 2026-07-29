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
    private var apiURL: String { ProcessInfo.processInfo.environment["HEALD_API_URL"] ?? "https://heald.sh/api/ingest" }
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
        let icloud = await store.icloud
        let gpu = await store.gpu
        let bluetooth = await store.bluetooth
        let wifi = await store.wifi
        let security = await store.security
        let ssdWear = await store.ssdWear
        let timeMachine = await store.timeMachine
        let loginItems = await store.loginItems
        let memoryLeak = await store.memoryLeak
        let focus = await store.focus

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
            "clientVersion": HealdApp.version,
            "cpu": cpuDict,
            "ram": ramDict,
            "disk": diskDict,
            "processes": processDict,
            "network": networkDict,
            "uptime": uptimeDict,
            "thermal": thermal.thermalState.rawValue,
        ]
        var icloudDict: [String: Any]? = nil
        if icloud.timestamp != Date.distantPast {
            icloudDict = [
                "isEnabled": icloud.isEnabled,
                "optimizeStorage": icloud.optimizeStorage,
                "localFiles": icloud.localFiles,
                "cloudFiles": icloud.cloudFiles,
                "syncPercent": round(icloud.syncPercent * 10) / 10,
                "directories": icloud.directories,
                "evictedDirs": icloud.evictedDirs,
                "conflicts": icloud.conflicts,
                "docsSizeGB": round(Double(icloud.docsSize) / 1_073_741_824 * 100) / 100,
                "diskFreeGB": round(Double(icloud.diskFree) / 1_073_741_824 * 100) / 100,
                "birdRunning": icloud.birdRunning,
            ]
        }

        if let batteryDict { metrics["battery"] = batteryDict }
        if let benchmarkDict { metrics["benchmark"] = benchmarkDict }
        if let icloudDict { metrics["icloud"] = icloudDict }

        // GPU
        if gpu.timestamp != .distantPast {
            metrics["gpu"] = [
                "utilizationPercent": round(gpu.utilizationPercent * 1000) / 10,
                "inUseMemoryMB": gpu.inUseSystemMemoryBytes / 1_048_576,
                "allocatedMemoryMB": gpu.allocatedSystemMemoryBytes / 1_048_576,
                "deviceName": gpu.deviceName,
            ] as [String: Any]
        }

        // Bluetooth
        if bluetooth.timestamp != .distantPast && !bluetooth.devices.isEmpty {
            metrics["bluetooth"] = bluetooth.devices.map { device -> [String: Any] in
                var d: [String: Any] = [
                    "name": device.name,
                    "connected": device.isConnected,
                    "type": device.deviceType,
                ]
                if let battery = device.batteryPercent { d["batteryPercent"] = battery }
                return d
            }
        }

        // WiFi
        if wifi.timestamp != .distantPast, wifi.ssid != nil {
            metrics["wifi"] = [
                "ssid": wifi.ssid as Any,
                "rssi": wifi.rssi,
                "noise": wifi.noise,
                "snr": wifi.snr,
                "channel": wifi.channel,
                "channelBand": wifi.channelBand,
                "txRate": wifi.txRate,
                "signalQuality": wifi.signalQuality,
            ] as [String: Any]
        }

        // Security
        if security.timestamp != .distantPast {
            var secDict: [String: Any] = [
                "fileVaultEnabled": security.fileVaultEnabled,
                "firewallEnabled": security.firewallEnabled,
                "firewallStealthMode": security.firewallStealthMode,
                "gatekeeperEnabled": security.gatekeeperEnabled,
                "sipEnabled": security.sipEnabled,
                "securityScore": "\(security.securityScore)/4",
            ]
            if let v = security.xprotectVersion { secDict["xprotectVersion"] = v }
            if let age = security.xprotectSignatureAgeDays { secDict["xprotectSignatureAgeDays"] = age }
            if let rv = security.xprotectRemediatorVersion { secDict["xprotectRemediatorVersion"] = rv }
            metrics["security"] = secDict
        }

        // SSD Wear
        if ssdWear.timestamp != .distantPast {
            var ssdDict: [String: Any] = [:]
            if let pct = ssdWear.percentageUsed { ssdDict["percentageUsed"] = pct }
            if let spare = ssdWear.availableSpare { ssdDict["availableSpare"] = spare }
            if let tb = ssdWear.dataWrittenTB { ssdDict["dataWrittenTB"] = round(tb * 100) / 100 }
            if let hours = ssdWear.powerOnHours { ssdDict["powerOnHours"] = hours }
            if let life = ssdWear.estimatedLifeRemainingPercent { ssdDict["lifeRemainingPercent"] = life }
            if !ssdDict.isEmpty { metrics["ssdWear"] = ssdDict }
        }

        // Time Machine
        if timeMachine.timestamp != .distantPast {
            var tmDict: [String: Any] = [
                "isConfigured": timeMachine.isConfigured,
                "autoBackupEnabled": timeMachine.autoBackupEnabled,
            ]
            if let name = timeMachine.destinationName { tmDict["destinationName"] = name }
            if let hours = timeMachine.hoursSinceLastBackup { tmDict["hoursSinceLastBackup"] = round(hours * 10) / 10 }
            if let date = timeMachine.lastBackupDate { tmDict["lastBackupDate"] = ISO8601DateFormatter().string(from: date) }
            metrics["timeMachine"] = tmDict
        }

        // Login Items
        if loginItems.timestamp != .distantPast {
            metrics["loginItems"] = loginItems.items.map { item -> [String: Any] in
                var d: [String: Any] = ["name": item.name, "isHidden": item.isHidden]
                if let path = item.path { d["path"] = path }
                return d
            }
        }

        // Memory Leak Suspects
        if memoryLeak.timestamp != .distantPast && !memoryLeak.suspects.isEmpty {
            metrics["memoryLeaks"] = memoryLeak.suspects.map { s -> [String: Any] in
                ["pid": s.pid, "name": s.name, "currentMB": Int(s.currentMB),
                 "growthMB": Int(s.growthMB), "growthRateMBPerHour": Int(s.growthRateMBPerHour)] as [String: Any]
            }
        }

        // Focus Mode
        if focus.timestamp != .distantPast {
            metrics["focus"] = [
                "isActive": focus.isActive,
                "modeName": focus.modeName as Any,
            ] as [String: Any]
        }

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
