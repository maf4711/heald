import ArgumentParser
import Foundation

// MARK: - Doctor

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Install + self-heal + policy status"
    )

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let policy = PolicyPack.load()
        let identity = DeviceIdentity.identitySummary() // read-only: doctor never relocates/enrolls
        let device = DeviceIdentity.load()
        print("heald doctor v\(HealdApp.version) — Enterprise")
        print(String(repeating: "─", count: 48))
        print("Edition:    enterprise (native self-heal)")
        print("Meister:    not required / not linked")
        print("Preset:     \(policy.preset)")
        print("Consent:    \(policy.consent.rawValue)  selfHeal=\(policy.selfHealEnabled)")
        print("Cloud:      \(policy.allowsCloud() ? "enabled" : "DISABLED (policy/HEALD_CLOUD=0)")")
        print("PII redact: \(policy.piiRedaction)")
        print("SIEM:       \(policy.siemSyslogEnabled || !(ProcessInfo.processInfo.environment["HEALD_SIEM_HOST"] ?? "").isEmpty ? "on" : "off")")
        print("MDM policy: \(PolicyPack.hasManagedPolicy() ? "active (sh.heald overrides)" : "none")")
        print("Device:     \(device.map { $0.deviceId } ?? "not enrolled — heald enroll")")
        print("identity:   \(identity)")
        print("Auth:       \(DeviceIdentity.bearerToken() != nil ? "token/key present" : "none")")
        print("Sudo ticket:\(SudoTicket.hasTicket() ? "yes" : "no — heald sudo-setup")")
        print("Policy:     \(PolicyPack.policyURL.path)")
        print("Binary:     \(CommandLine.arguments.first ?? "heald")")

        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        print("Data dir:   \(dataDir.path) \(FileManager.default.fileExists(atPath: dataDir.path) ? "✓" : "—")")

        let installBin = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/heald/heald").path
        print("Install:    \(installBin) \(FileManager.default.isExecutableFile(atPath: installBin) ? "✓" : "missing")")

        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.heald.daemon.plist").path
        print("LaunchAgent:\(plist) \(FileManager.default.fileExists(atPath: plist) ? "✓" : "missing")")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-x", "heald"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if task.terminationStatus == 0, !out.isEmpty {
            print("Daemon:     running (PID \(out.split(separator: "\n").first ?? "?"))")
        } else {
            print("Daemon:     not running")
        }

        print(String(repeating: "─", count: 48))
        let autoAllowed = AutoUpdateService.isAutoUpdateAllowed(policy: policy)
        let autoOffPlist = launchAgentEnvValue("HEALD_AUTO_UPDATE") == "0"
        print("Update URL: \(AutoUpdateService.updateManifestURL())")
        print("Auto-update:\(autoAllowed ? "ON" : "OFF") interval=\(AutoUpdateService.pollIntervalSec())s\(AutoUpdateService.isManagedInstall() ? " managed" : " non-managed")\(autoOffPlist ? " (plist off)" : "")")
        if let st = AutoUpdateService.readStatus() {
            let state = st["state"] as? String ?? "?"
            let detail = st["detail"] as? String ?? ""
            let remote = st["remoteVersion"] as? String
            print("Update last:\(state) \(detail)\(remote.map { " remote=\($0)" } ?? "")")
        }
        print("Features:   policy · mdm · enroll · approve · bank · pii · siem · compliance v2")
        print("CLI:        policy | enroll | approve | compliance | maintain | heal | free | update")
        let sh = dataDir.appendingPathComponent("self_heal.json")
        if let data = try? Data(contentsOf: sh),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let c = obj["consent"] { print("Self-heal:  consent=\(c)") }
            if let p = obj["ram_pressure"] { print("            ram_pressure=\(p)") }
            if let d = obj["disk_free_pct"] as? Double, d >= 0 {
                print(String(format: "            disk_free=%.1f%%", d))
            }
        }
        print(String(repeating: "─", count: 48))
    }
}
