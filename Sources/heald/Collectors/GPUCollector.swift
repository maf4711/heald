import Foundation
import IOKit
import ServiceLifecycle
import OSLog

/// Monitors GPU utilization on Apple Silicon via IOKit accelerator statistics.
struct GPUCollector: Service {
    let store: MetricsStore

    func run() async throws {
        Logger.collector.info("GPUCollector started")

        while true {
            let snapshot = readGPUMetrics()
            await store.updateGPU(snapshot)

            if snapshot.utilizationPercent > 0 {
                Logger.collector.debug(
                    "GPU: \(snapshot.utilizationPercent * 100, format: .fixed(precision: 1))% util, VRAM in-use: \(snapshot.inUseSystemMemoryBytes / 1_048_576)MB — \(snapshot.deviceName)"
                )
            }

            try await Task.sleep(for: .seconds(10))
        }
    }

    private func readGPUMetrics() -> GPUSnapshot {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")

        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return .empty
        }
        defer { IOObjectRelease(iterator) }

        var bestUtilization: Double = 0
        var bestInUse: Int64 = 0
        var bestAllocated: Int64 = 0
        var deviceName = "Apple GPU"

        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            defer { IOObjectRelease(entry) }

            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any] else {
                entry = IOIteratorNext(iterator)
                continue
            }

            // Device name
            if let name = props["IOClass"] as? String, name.contains("AGX") {
                deviceName = name
            }
            if let name = props["model"] as? Data, let modelStr = String(data: name, encoding: .utf8) {
                deviceName = modelStr.trimmingCharacters(in: .controlCharacters)
            }

            // GPU utilization from PerformanceStatistics
            if let perfStats = props["PerformanceStatistics"] as? [String: Any] {
                // Device Utilization % is reported as 0-100 integer on Apple Silicon
                if let utilization = perfStats["Device Utilization %"] as? Int {
                    bestUtilization = max(bestUtilization, Double(utilization) / 100.0)
                }
                // Alternative key on some hardware
                if let utilization = perfStats["GPU Activity(%)"] as? Int {
                    bestUtilization = max(bestUtilization, Double(utilization) / 100.0)
                }

                if let inUse = perfStats["In use system memory"] as? Int64 {
                    bestInUse = max(bestInUse, inUse)
                }
                // Alternative key format
                if let inUse = perfStats["inUseSystemMemory"] as? Int64 {
                    bestInUse = max(bestInUse, inUse)
                }
                if let allocated = perfStats["Allocated system memory"] as? Int64 {
                    bestAllocated = max(bestAllocated, allocated)
                }
                if let allocated = perfStats["allocatedSystemMemory"] as? Int64 {
                    bestAllocated = max(bestAllocated, allocated)
                }
            }

            entry = IOIteratorNext(iterator)
        }

        return GPUSnapshot(
            utilizationPercent: bestUtilization,
            inUseSystemMemoryBytes: bestInUse,
            allocatedSystemMemoryBytes: bestAllocated,
            deviceName: deviceName,
            timestamp: Date()
        )
    }
}
