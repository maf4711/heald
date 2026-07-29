import Foundation

/// Compliance-style inventory export (JSON) for audit packs.
enum ComplianceExport {
    static func generate(store: MetricsStore) async -> [String: Any] {
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let policy = await PolicyStore.shared.current()
        let sec = await store.security
        let disk = await store.disk
        let bat = await store.battery
        let ram = await store.ram
        let cpu = await store.cpu

        let root = disk.volumes.first(where: { $0.mountPoint == "/" })
        let freePct: Double? = {
            guard let r = root, r.totalBytes > 0 else { return nil }
            return Double(r.freeBytes) / Double(r.totalBytes) * 100
        }()

        return [
            "schema": "heald.compliance/v1",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "host": host,
            "user": NSUserName(),
            "edition": "enterprise",
            "policy": [
                "consent": policy.consent.rawValue,
                "self_heal": policy.selfHealEnabled,
                "firewall_enforce": policy.firewallEnforce,
                "safe_softwareupdate": policy.safeSoftwareUpdate,
            ],
            "security": [
                "filevault": sec.fileVaultEnabled,
                "firewall": sec.firewallEnabled,
                "gatekeeper": sec.gatekeeperEnabled,
                "sip": sec.sipEnabled,
                "xprotect_version": sec.xprotectVersion as Any,
            ],
            "system": [
                "cpu_overall": cpu.overall,
                "ram_pressure": ram.pressureLevel,
                "disk_free_pct": freePct as Any,
                "battery_present": bat.isPresent,
                "battery_health_pct": bat.maxCapacityPercent,
                "battery_cycles": bat.cycleCount,
                "battery_condition": bat.condition,
            ],
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "heald_version": HealdApp.version,
        ]
    }

    static func write(store: MetricsStore) async -> URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/compliance")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = dir.appendingPathComponent("compliance-\(stamp).json")
        let obj = await generate(store: store)
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
            // also latest
            try? data.write(
                to: dir.appendingPathComponent("compliance-latest.json"),
                options: .atomic
            )
        }
        return url
    }
}
