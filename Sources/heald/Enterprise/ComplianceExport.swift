import Foundation

/// Compliance inventory export (JSON) for audit packs — v2 bank pilot.
enum ComplianceExport {
    static func generate(store: MetricsStore) async -> [String: Any] {
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let policy = await PolicyStore.shared.current()
        let sec = await store.security
        let disk = await store.disk
        let bat = await store.battery
        let ram = await store.ram
        let cpu = await store.cpu
        let device = DeviceIdentity.load()
        let mdm = DeviceIdentity.mdmEnrollmentStatus()

        let root = disk.volumes.first(where: { $0.mountPoint == "/" })
        let freePct: Double? = {
            guard let r = root, r.totalBytes > 0 else { return nil }
            return Double(r.freeBytes) / Double(r.totalBytes) * 100
        }()

        // Prefer live store; fall back to one-shot shell probes
        let fileVault = sec.timestamp != .distantPast ? sec.fileVaultEnabled : probeFileVault()
        let firewall = sec.timestamp != .distantPast ? sec.firewallEnabled : probeFirewall()
        let gatekeeper = sec.timestamp != .distantPast ? sec.gatekeeperEnabled : probeGatekeeper()
        let sip = sec.timestamp != .distantPast ? sec.sipEnabled : probeSIP()

        let cis = cisSubset(
            fileVault: fileVault,
            firewall: firewall,
            gatekeeper: gatekeeper,
            sip: sip,
            freePct: freePct
        )

        return [
            "schema": "heald.compliance/v2",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "host": host,
            "user": NSUserName(),
            "edition": "enterprise",
            "heald_version": HealdApp.version,
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "device": [
                "deviceId": device?.deviceId as Any,
                "hardwareUUID": (device?.hardwareUUID ?? DeviceIdentity.hardwareUUID()) as Any,
                "serialNumber": (device?.serialNumber ?? DeviceIdentity.serialNumber()) as Any,
                "enrolledAt": device?.enrolledAt as Any,
                "hasDeviceToken": (device?.token.isEmpty == false),
            ] as [String: Any],
            "mdm": mdm,
            "policy": [
                "preset": policy.preset,
                "consent": policy.consent.rawValue,
                "self_heal": policy.selfHealEnabled,
                "process_kill": policy.processKillEnabled,
                "cloud_enabled": policy.cloudEnabled,
                "allows_cloud": policy.allowsCloud(),
                "pii_redaction": policy.piiRedaction,
                "firewall_enforce": policy.firewallEnforce,
                "safe_softwareupdate": policy.safeSoftwareUpdate,
                "siem_syslog": policy.siemSyslogEnabled,
            ] as [String: Any],
            "security": [
                "filevault": fileVault,
                "firewall": firewall,
                "gatekeeper": gatekeeper,
                "sip": sip,
                "xprotect_version": sec.xprotectVersion as Any,
            ] as [String: Any],
            "cis_macos_subset": cis,
            "system": [
                "cpu_overall": cpu.overall,
                "ram_pressure": ram.pressureLevel,
                "disk_free_pct": freePct as Any,
                "battery_present": bat.isPresent,
                "battery_health_pct": bat.maxCapacityPercent,
                "battery_cycles": bat.cycleCount,
                "battery_condition": bat.condition,
            ] as [String: Any],
            "privacy": [
                "outbound_pii_redaction": policy.piiRedaction,
                "cloud_mode": policy.allowsCloud() ? "enabled" : "disabled",
            ] as [String: Any],
        ]
    }

    private static func probeFileVault() -> Bool {
        let r = ShellRunner.run("/usr/bin/fdesetup", arguments: ["status"], timeoutSeconds: 8)
        return r.output.contains("FileVault is On")
    }

    private static func probeFirewall() -> Bool {
        let r = ShellRunner.run(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            arguments: ["--getglobalstate"],
            timeoutSeconds: 5
        )
        return r.output.lowercased().contains("enabled")
    }

    private static func probeGatekeeper() -> Bool {
        let r = ShellRunner.run("/usr/sbin/spctl", arguments: ["--status"], timeoutSeconds: 5)
        return r.output.lowercased().contains("assessments enabled")
    }

    private static func probeSIP() -> Bool {
        let r = ShellRunner.run("/usr/bin/csrutil", arguments: ["status"], timeoutSeconds: 5)
        return r.output.lowercased().contains("enabled")
    }

    /// Minimal CIS-inspired checks (report-only, not full benchmark).
    private static func cisSubset(
        fileVault: Bool,
        firewall: Bool,
        gatekeeper: Bool,
        sip: Bool,
        freePct: Double?
    ) -> [[String: Any]] {
        [
            cisRow("disk_encryption_filevault", fileVault, "CIS-ish: FileVault enabled"),
            cisRow("firewall_enabled", firewall, "CIS-ish: Application Firewall on"),
            cisRow("gatekeeper_enabled", gatekeeper, "CIS-ish: Gatekeeper on"),
            cisRow("sip_enabled", sip, "CIS-ish: System Integrity Protection on"),
            cisRow(
                "disk_space_ok",
                (freePct ?? 100) >= 10,
                "Operational: root free ≥ 10%"
            ),
            cisRow(
                "auto_login_disabled_unknown",
                true,
                "Placeholder: verify auto-login disabled in MDM"
            ),
        ]
    }

    private static func cisRow(_ id: String, _ pass: Bool, _ title: String) -> [String: Any] {
        ["id": id, "pass": pass, "title": title, "severity": pass ? "pass" : "fail"]
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
            try? data.write(
                to: dir.appendingPathComponent("compliance-latest.json"),
                options: .atomic
            )
        }
        return url
    }
}
