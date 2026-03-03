import Foundation
import Darwin
import IOKit
import ServiceLifecycle
import OSLog

struct DiskCollector: Service {
    let store: MetricsStore

    func run() async throws {
        var cycle = 0
        var prevIO: [String: DiskIOCounters] = [:]  // BSD name -> previous counters

        try await withGracefulShutdownHandler {
            while true {
                var volumes: [VolumeSpaceInfo] = []
                var ioDeltas: [DiskIODelta] = []
                var smartInfos: [SMARTInfo] = []

                // Disk I/O — every 5s
                let (deltas, newCounters) = readDiskIO(previous: prevIO)
                ioDeltas = deltas
                prevIO = newCounters

                // Disk space — every 60s (cycle % 12 == 0)
                if cycle % 12 == 0 {
                    volumes = readDiskSpace()
                    Logger.collector.debug("Disk space: \(volumes.count) volumes")
                }

                // SMART — every 300s (cycle % 60 == 0)
                if cycle % 60 == 0 {
                    smartInfos = readSMART()
                    Logger.collector.info("SMART: \(smartInfos.count) drives checked")
                    for info in smartInfos where info.status == "Failing" {
                        Logger.collector.warning("SMART failing: \(info.bsdName)")
                    }
                }

                Logger.collector.debug("Disk I/O: \(ioDeltas.count) drives")

                let snapshot = DiskSnapshot(
                    volumes: volumes,
                    io: ioDeltas,
                    smart: smartInfos,
                    timestamp: Date()
                )
                await store.updateDisk(snapshot)
                cycle += 1
                try await Task.sleep(for: .seconds(5))
            }
        } onGracefulShutdown: {
            // Task.sleep throws CancellationError on shutdown, breaking the while loop cleanly.
        }
    }
}

// MARK: - Disk Space (MON-03)

private func readDiskSpace() -> [VolumeSpaceInfo] {
    guard let urls = FileManager.default.mountedVolumeURLs(
        includingResourceValuesForKeys: [.volumeNameKey],
        options: .skipHiddenVolumes
    ) else {
        return []
    }

    var results: [VolumeSpaceInfo] = []
    for url in urls {
        var stat = statfs()
        // Use statfs NOT statvfs — statvfs returns incorrect f_bsize on macOS (256x too large)
        guard url.path.withCString({ statfs($0, &stat) == 0 }) else { continue }

        let totalBytes = Int64(stat.f_blocks) * Int64(stat.f_bsize)
        let freeBytes = Int64(stat.f_bfree) * Int64(stat.f_bsize)

        // Extract mount point from f_mntonname (tuple of CChar)
        let mountPoint: String = withUnsafePointer(to: stat.f_mntonname) { ptr in
            String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
        }

        // Get volume name from resource values or fall back to last path component
        let volumeName: String
        if let resourceValues = try? url.resourceValues(forKeys: [.volumeNameKey]),
           let name = resourceValues.volumeName {
            volumeName = name
        } else {
            volumeName = url.lastPathComponent
        }

        results.append(VolumeSpaceInfo(
            mountPoint: mountPoint,
            volumeName: volumeName,
            totalBytes: totalBytes,
            freeBytes: freeBytes
        ))
    }
    return results
}

// MARK: - Disk I/O (MON-04)

private func readDiskIO(previous: [String: DiskIOCounters]) -> ([DiskIODelta], [String: DiskIOCounters]) {
    var newCounters: [String: DiskIOCounters] = [:]
    var deltas: [DiskIODelta] = []

    // Enumerate disk0..disk9 heuristic for physical disks
    for i in 0...9 {
        let bsdName = "disk\(i)"
        guard let counters = readIOCounters(for: bsdName) else { continue }
        newCounters[bsdName] = counters

        // First cycle: store baseline, return empty deltas
        guard let prev = previous[bsdName] else { continue }

        let readDelta = counters.readBytes - prev.readBytes
        let writeDelta = counters.writeBytes - prev.writeBytes

        // Only include if deltas are non-negative (counter reset guard)
        if readDelta >= 0 && writeDelta >= 0 {
            deltas.append(DiskIODelta(
                readBytes: readDelta,
                writeBytes: writeDelta,
                interval: 5.0
            ))
        }
    }

    return (deltas, newCounters)
}

private func readIOCounters(for bsdName: String) -> DiskIOCounters? {
    // Look up the IORegistry service by BSD name
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
    )
    guard service != IO_OBJECT_NULL else { return nil }
    defer { IOObjectRelease(service) }

    // Traverse parents to find IOBlockStorageDriver (max 10 depth to avoid infinite loop on virtual disks)
    var current = service
    IOObjectRetain(current)
    var depth = 0
    var foundDriver: io_object_t = IO_OBJECT_NULL

    while depth < 10 {
        if IOObjectConformsTo(current, "IOBlockStorageDriver") != 0 {
            foundDriver = current
            break
        }
        var parent: io_registry_entry_t = IO_OBJECT_NULL
        let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
        IOObjectRelease(current)
        guard kr == KERN_SUCCESS, parent != IO_OBJECT_NULL else { break }
        current = parent
        depth += 1
    }

    // Release current if we didn't find a driver and it's still held
    if foundDriver == IO_OBJECT_NULL {
        if current != service { IOObjectRelease(current) }
        return nil
    }

    defer { IOObjectRelease(foundDriver) }

    // Read the Statistics dictionary from IOBlockStorageDriver
    var propsRef: Unmanaged<CFMutableDictionary>?
    let kr = IORegistryEntryCreateCFProperties(foundDriver, &propsRef, kCFAllocatorDefault, 0)
    guard kr == KERN_SUCCESS, let props = propsRef?.takeRetainedValue() as? [String: Any] else {
        return nil
    }

    guard let stats = props["Statistics"] as? [String: Any] else { return nil }

    let readBytes = (stats["Bytes (Read)"] as? Int64) ?? 0
    let writeBytes = (stats["Bytes (Write)"] as? Int64) ?? 0

    return DiskIOCounters(readBytes: readBytes, writeBytes: writeBytes)
}

// MARK: - SMART Health (MON-08)

private func readSMART() -> [SMARTInfo] {
    var results: [SMARTInfo] = []

    for i in 0...9 {
        let bsdName = "disk\(i)"

        // Only query physical drives that exist
        let checkService = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOBSDNameMatching(kIOMainPortDefault, 0, bsdName)
        )
        guard checkService != IO_OBJECT_NULL else { continue }
        IOObjectRelease(checkService)

        guard let plist = runDiskUtil(bsdName: bsdName) else { continue }

        // Extract SMART status
        let smartStatus = plist["SMARTStatus"] as? String ?? "Not Supported"

        // Extract NVMe/SMART device-specific keys (may not exist for all drives)
        let specificKeys = plist["SMARTDeviceSpecificKeysMayVaryNotGuaranteed"] as? [String: Any]

        let availableSpare = specificKeys?["AVAILABLE_SPARE"] as? Int
        let percentageUsed = specificKeys?["PERCENTAGE_USED"] as? Int
        let temperature = specificKeys?["TEMPERATURE"] as? Int
        let powerOnHours = specificKeys?["POWER_ON_HOURS_0"] as? Int

        results.append(SMARTInfo(
            bsdName: bsdName,
            status: smartStatus,
            availableSpare: availableSpare,
            percentageUsed: percentageUsed,
            temperature: temperature,
            powerOnHours: powerOnHours
        ))
    }

    return results
}

private func runDiskUtil(bsdName: String) -> [String: Any]? {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
    task.arguments = ["info", "-plist", bsdName]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()  // suppress stderr

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        Logger.collector.error("diskutil failed for \(bsdName): \(error)")
        return nil
    }

    guard task.terminationStatus == 0 else { return nil }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard !data.isEmpty else { return nil }

    guard let plist = try? PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
    ) as? [String: Any] else {
        return nil
    }

    return plist
}
