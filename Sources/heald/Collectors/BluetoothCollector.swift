import Foundation
import ServiceLifecycle
import OSLog

/// Monitors connected Bluetooth devices and their battery levels.
/// Uses system_profiler SPBluetoothDataType (no private frameworks needed).
struct BluetoothCollector: Service {
    let store: MetricsStore
    let activityLog: ActivityLog

    func run() async throws {
        Logger.collector.info("BluetoothCollector started")

        while true {
            let snapshot = readBluetoothDevices()
            await store.updateBluetooth(snapshot)

            // Warn on low battery
            for device in snapshot.devices {
                if let battery = device.batteryPercent, battery <= 10 {
                    Logger.collector.warning("Bluetooth low battery: \(device.name) at \(battery)%")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .bluetoothLowBattery,
                        summary: "\(device.name) battery at \(battery)%",
                        detail: "Device: \(device.name) (\(device.deviceType))"
                    ))
                }
            }

            try await Task.sleep(for: .seconds(120)) // 2 minutes
        }
    }

    private func readBluetoothDevices() -> BluetoothSnapshot {
        let result = ShellRunner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPBluetoothDataType", "-detailLevel", "full", "-xml"]
        )
        guard result.succeeded, let data = result.output.data(using: .utf8) else {
            return .empty
        }

        guard let plistArray = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [[String: Any]],
              let root = plistArray.first,
              let items = root["_items"] as? [[String: Any]] else {
            return .empty
        }

        var devices: [BluetoothDevice] = []

        for controller in items {
            // Connected devices are under various keys depending on macOS version
            let deviceSections = [
                "device_connected", "device_not_connected",
                "device_title"
            ]

            for sectionKey in deviceSections {
                guard let deviceList = controller[sectionKey] as? [[String: Any]] else { continue }

                for deviceDict in deviceList {
                    // Each entry is a dict with device name as key
                    for (name, value) in deviceDict {
                        guard let info = value as? [String: Any] else { continue }

                        let address = info["device_address"] as? String ?? ""
                        let connected = (info["device_connected"] as? String) == "attrib_Yes" ||
                                       sectionKey == "device_connected"

                        // Battery level
                        var batteryPercent: Int? = nil
                        if let batteryStr = info["device_batteryPercent"] as? String {
                            batteryPercent = Int(batteryStr)
                        }
                        if let batteryLevel = info["device_batteryLevelMain"] as? String {
                            batteryPercent = Int(batteryLevel)
                        }
                        // Also check individual battery keys (L/R for AirPods)
                        if batteryPercent == nil {
                            let batteryKeys = ["device_batteryLevelLeft", "device_batteryLevelRight", "device_batteryLevelCase"]
                            for key in batteryKeys {
                                if let val = info[key] as? String, let level = Int(val) {
                                    // Use minimum of all batteries
                                    batteryPercent = min(batteryPercent ?? level, level)
                                }
                            }
                        }

                        let minorType = info["device_minorType"] as? String ?? "Unknown"
                        let deviceType = classifyDevice(minorType: minorType, name: name)

                        if connected || batteryPercent != nil {
                            devices.append(BluetoothDevice(
                                name: name,
                                address: address,
                                batteryPercent: batteryPercent,
                                isConnected: connected,
                                deviceType: deviceType
                            ))
                        }
                    }
                }
            }
        }

        return BluetoothSnapshot(devices: devices, timestamp: Date())
    }

    private func classifyDevice(minorType: String, name: String) -> String {
        let lower = (minorType + " " + name).lowercased()
        if lower.contains("keyboard") { return "Keyboard" }
        if lower.contains("mouse") || lower.contains("trackpad") { return "Mouse" }
        if lower.contains("headphone") || lower.contains("airpod") || lower.contains("headset") { return "Headphones" }
        if lower.contains("gamepad") || lower.contains("controller") { return "Gamepad" }
        if lower.contains("speaker") || lower.contains("homepod") { return "Speaker" }
        if lower.contains("pencil") { return "Stylus" }
        return "Peripheral"
    }
}
