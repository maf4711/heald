import ArgumentParser
import Foundation
import ServiceLifecycle
import OSLog

/// Entry point: accept common version spellings before ArgumentParser.
/// Supports: `--version`, `-version`, `-V`, `version`
@main
enum HealdMain {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if isVersionRequest(args) {
            print(HealdApp.version)
            return
        }
        await HealdApp.main()
    }

    private static func isVersionRequest(_ args: [String]) -> Bool {
        // Only treat as version when the sole (or first-and-only) intent is version.
        guard args.count == 1 else { return false }
        switch args[0] {
        case "--version", "-version", "-V", "-v", "version":
            return true
        default:
            return false
        }
    }
}

struct HealdApp: AsyncParsableCommand {
    static let version = "3.5.1"

    static let configuration = CommandConfiguration(
        commandName: "heald",
        abstract: "heald Enterprise — self-healing macOS (native, no Meister)",
        version: version,
        subcommands: [
            RunCommand.self,
            DoctorCommand.self,
            StatusCommand.self,
            MaintainCommand.self,
            HealCommand.self,
            AutofixCommand.self,
            StorageCommand.self,
            FreeCommand.self,
            PolicyCommand.self,
            ComplianceCommand.self,
            EnrollCommand.self,
            ApproveCommand.self,
            SudoSetupCommand.self,
            UpdateCommand.self,
            VersionCommand.self,
        ],
        defaultSubcommand: RunCommand.self
    )
}

// MARK: - Run

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the heald enterprise daemon"
    )

    func run() async throws {
        Logger.lifecycle.info("heald \(HealdApp.version) enterprise starting")
        _ = PolicyPack.load()
        let store = MetricsStore()
        let service = HealdService(store: store)
        let group = ServiceGroup(
            services: [service],
            gracefulShutdownSignals: [.sigterm, .sigint],
            logger: .init(label: "com.heald.daemon")
        )
        try await group.run()
        Logger.lifecycle.info("heald stopped cleanly")
    }
}

// MARK: - Doctor

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Install + self-heal + policy status"
    )

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let policy = PolicyPack.load()
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

// MARK: - Version

struct VersionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version",
        abstract: "Print heald version"
    )
    func run() async throws {
        print(HealdApp.version)
    }
}

// MARK: - Update

struct UpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Check heald.sh for a newer client binary and install it"
    )

    @Flag(name: .long, help: "Install even if remote version is not newer")
    var force: Bool = false

    @Flag(name: .long, help: "Only print remote vs local version")
    var check: Bool = false

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("heald update v\(HealdApp.version)")
        print("Manifest: \(AutoUpdateService.updateManifestURL())")

        do {
            let manifest = try await AutoUpdateService.fetchManifest()
            print("Local:    \(HealdApp.version)")
            print("Remote:   \(manifest.version)")
            print("URL:      \(manifest.url)")
            if let sha = manifest.sha256, !sha.isEmpty {
                print("SHA256:   \(sha.prefix(16))…")
            }
            if let notes = manifest.notes, !notes.isEmpty {
                print("Notes:    \(notes)")
            }

            if check {
                let newer = AutoUpdateService.isNewer(manifest.version, than: HealdApp.version)
                print(newer ? "Status:   update available" : "Status:   up to date")
                throw ExitCode(newer ? 1 : 0)
            }

            let applied = try await AutoUpdateService.checkAndApply(force: force)
            if applied {
                print("Installed \(manifest.version) → \(AutoUpdateService.installBinaryURL().path)")
                print("Restarting daemon…")
                let uid = getuid()
                _ = ShellRunner.run(
                    "/bin/launchctl",
                    arguments: ["kickstart", "-k", "gui/\(uid)/com.heald.daemon"],
                    timeoutSeconds: 10
                )
                print("Done. Verify: heald --version && heald doctor")
            } else {
                print("Already up to date.")
            }
        } catch let code as ExitCode {
            throw code
        } catch {
            print("Error: \(error.localizedDescription)")
            throw ExitCode(1)
        }
    }
}

// MARK: - Status

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Self-heal status JSON"
    )

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let sh = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/self_heal.json")
        if let s = try? String(contentsOf: sh, encoding: .utf8) {
            print(s)
        } else {
            print("{\"schema\":\"heald.self_heal/v1\",\"note\":\"no status yet — start daemon\"}")
        }
    }
}

// MARK: - Maintain / Heal / Autofix / Storage / Free (unchanged native)

struct MaintainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maintain",
        abstract: "Run native quick|deep maintenance now"
    )
    @Option(name: .shortAndLong, help: "quick|deep")
    var profile: String = "quick"

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let activityLog = try openActivityLog()
        let ai = AppleIntelligenceClient()
        await ai.checkAvailability()
        print("heald maintain —\(profile) (native enterprise)...")
        switch profile.lowercased() {
        case "quick":
            await MaintainProfiles.quick(activityLog: activityLog, ai: ai)
        case "deep":
            await MaintainProfiles.deep(activityLog: activityLog, ai: ai)
        default:
            print("Unknown profile — use quick|deep")
            throw ExitCode(2)
        }
        print("done")
    }
}

struct HealCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heal",
        abstract: "Proactive healer now"
    )
    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("heald heal...")
        await ProactiveHealer().run(activityLog: try openActivityLog())
        print("done")
    }
}

struct AutofixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autofix",
        abstract: "Deterministic autofix now"
    )
    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let log = try openActivityLog()
        let engine = AutofixEngine()
        print("heald autofix...")
        await engine.quarantineOrphanAgents(activityLog: log)
        await engine.enableFirewall(activityLog: log)
        await engine.brewCleanupLight(activityLog: log)
        print("done")
    }
}

struct StorageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "storage",
        abstract: "Safe-to-delete size report"
    )
    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        StorageReport.printReport()
    }
}

struct FreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "free",
        abstract: "RAM purge (sudo ticket)"
    )
    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("heald free...")
        await RAMPurge().purge(activityLog: try openActivityLog())
        print("done")
    }
}

// MARK: - Policy

struct PolicyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "policy",
        abstract: "Show or set enterprise policy (consent, bank preset, cloud, webhooks)"
    )

    @Option(name: .long, help: "auto|ask|log")
    var consent: String?

    @Option(name: .long, help: "Apply preset: bank|lab")
    var preset: String?

    @Flag(name: .long, help: "Disable cloud push (bank default)")
    var cloudOff: Bool = false

    @Flag(name: .long, help: "Enable cloud push")
    var cloudOn: Bool = false

    @Flag(name: .long, help: "Enable Slack webhook path (set URL in file)")
    var enableWebhook: Bool = false

    @Option(name: .long, help: "Slack incoming webhook URL")
    var webhookURL: String?

    @Flag(name: .long, help: "Opt-in safe softwareupdate in maintenance window")
    var enableSafeUpdate: Bool = false

    @Option(name: .long, help: "SIEM syslog host (enables UDP sink)")
    var siemHost: String?

    @Flag(name: .long, help: "Enable client auto-update from heald.sh")
    var autoUpdateOn: Bool = false

    @Flag(name: .long, help: "Disable client auto-update")
    var autoUpdateOff: Bool = false

    @Flag(name: .long, help: "Print path and exit")
    var path: Bool = false

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        if path {
            print(PolicyPack.policyURL.path)
            return
        }
        var p = PolicyPack.load()
        var changed = false

        if let name = preset?.lowercased() {
            switch name {
            case "bank":
                p = PolicyPack.bankPreset()
                changed = true
            case "lab", "default", "standard":
                p = PolicyPack.labPreset()
                changed = true
            default:
                print("Unknown preset '\(name)' — use bank|lab")
                throw ExitCode(2)
            }
        }

        if let c = consent, let mode = ConsentMode(rawValue: c) {
            p.consent = mode
            changed = true
        }
        if cloudOff {
            p.cloudEnabled = false
            changed = true
        }
        if cloudOn {
            p.cloudEnabled = true
            changed = true
        }
        if enableWebhook {
            p.webhookEnabled = true
            changed = true
        }
        if let u = webhookURL {
            p.slackWebhookURL = u
            p.webhookEnabled = true
            changed = true
        }
        if enableSafeUpdate {
            p.safeSoftwareUpdate = true
            changed = true
        }
        if let host = siemHost {
            p.siemSyslogHost = host
            p.siemSyslogEnabled = true
            changed = true
        }
        if autoUpdateOn {
            p.autoUpdateEnabled = true
            changed = true
        }
        if autoUpdateOff {
            p.autoUpdateEnabled = false
            changed = true
        }
        if changed {
            p.save()
            await PolicyStore.shared.reload()
            print("Policy updated → \(PolicyPack.policyURL.path)")
        }
        if let data = try? Data(contentsOf: PolicyPack.policyURL),
           let s = String(data: data, encoding: .utf8) {
            print(s)
        }
    }
}

// MARK: - Enroll (device token)

struct EnrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "enroll",
        abstract: "Create per-device fleet identity + token (bank auth)"
    )

    @Flag(name: .long, help: "Rotate token even if enrolled")
    var force: Bool = false

    @Flag(name: .long, help: "Show existing enrollment only")
    var show: Bool = false

    @Flag(name: .long, help: "POST device to fleet /api/enroll (needs HEALD_ADMIN_KEY)")
    var register: Bool = false

    @Option(name: .long, help: "Fleet base URL (default https://heald.sh)")
    var fleetURL: String?

    @Option(name: .long, help: "Admin API key for register (or HEALD_ADMIN_KEY / HEALD_API_KEY)")
    var adminKey: String?

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        if show {
            if let d = DeviceIdentity.load() {
                print("deviceId:  \(d.deviceId)")
                print("hostname:  \(d.hostname)")
                print("serial:    \(d.serialNumber ?? "—")")
                print("hwUUID:    \(d.hardwareUUID ?? "—")")
                print("enrolled:  \(d.enrolledAt)")
                print("token:     \(d.token.prefix(8))… (\(d.token.count) hex chars)")
                print("path:      \(DeviceIdentity.deviceURL.path)")
                print("hint:      heald enroll --register  (admin key) or HEALD_DEVICE_TOKENS")
            } else {
                print("Not enrolled — run: heald enroll")
                throw ExitCode(1)
            }
            return
        }
        let d = try DeviceIdentity.enroll(force: force)
        print("Enrolled heald device")
        print("deviceId:  \(d.deviceId)")
        print("serial:    \(d.serialNumber ?? "—")")
        print("token:     \(d.token)")
        print("path:      \(DeviceIdentity.deviceURL.path) (mode 600)")

        if register {
            let base = fleetURL
                ?? ProcessInfo.processInfo.environment["HEALD_FLEET_URL"]
                ?? "https://heald.sh"
            let key = adminKey
                ?? ProcessInfo.processInfo.environment["HEALD_ADMIN_KEY"]
                ?? ProcessInfo.processInfo.environment["HEALD_API_KEY"]
                ?? ""
            guard !key.isEmpty else {
                print("Error: --register needs HEALD_ADMIN_KEY or --admin-key")
                throw ExitCode(2)
            }
            guard let url = URL(string: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/enroll") else {
                print("Error: bad fleet URL")
                throw ExitCode(2)
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            let body: [String: Any] = [
                "deviceId": d.deviceId,
                "token": d.token,
                "hostname": d.hostname,
                "serialNumber": d.serialNumber as Any,
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 15
            let (data, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            let text = String(data: data, encoding: .utf8) ?? ""
            if code == 200 {
                print("Registered with fleet \(url.absoluteString)")
            } else {
                print("Fleet register failed HTTP \(code): \(text.prefix(200))")
                throw ExitCode(1)
            }
        } else {
            print("")
            print("Next: heald enroll --register   # push token to fleet admin registry")
            print("  or: add token to HEALD_DEVICE_TOKENS / HEALD_API_KEYS on server")
        }
    }
}

// MARK: - Approve (consent=ask)

struct ApproveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "approve",
        abstract: "Record one-shot approval for a blocked self-heal action (consent=ask)"
    )

    @Argument(help: "Action key, e.g. ram_purge, disk_cleanup, firewall_on")
    var action: String

    @Option(name: .long, help: "Minutes until approval expires (default 60)")
    var ttlMinutes: Int = 60

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/approvals.json")
        var dict: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = obj
        }
        let exp = Date().addingTimeInterval(TimeInterval(ttlMinutes * 60))
        dict[action] = ISO8601DateFormatter().string(from: exp)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
        print("Approved '\(action)' until \(dict[action] ?? "?")")
        print("File: \(url.path)")
        print("Note: SelfHeal checks this file when consent=ask")
    }
}

// MARK: - Compliance

struct ComplianceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compliance",
        abstract: "Export compliance inventory JSON"
    )

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let store = MetricsStore()
        // best-effort one-shot collectors would be heavy; export current store zeros + live shell
        let url = await ComplianceExport.write(store: store)
        // enrich with live security via existing checkers? minimal: print path + body
        if let s = try? String(contentsOf: url, encoding: .utf8) {
            print(s)
        }
        fputs("wrote \(url.path)\n", stderr)
    }
}

// MARK: - Sudo setup

struct SudoSetupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sudo-setup",
        abstract: "Sudo ticket instructions / draft sudoers for enterprise heals"
    )

    @Flag(name: .long, help: "Write ~/.heald/sudoers.heald.draft")
    var write: Bool = false

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        print(SudoTicket.setupInstructions())
        print("Current ticket: \(SudoTicket.hasTicket() ? "ACTIVE" : "none")")
        if write {
            let url = SudoTicket.writeDraft()
            print("Draft written: \(url.path)")
        }
    }
}

// MARK: - Helpers

private func openActivityLog() throws -> ActivityLog {
    let path = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".heald/data/activity.ndjson").path
    try FileManager.default.createDirectory(
        atPath: (path as NSString).deletingLastPathComponent,
        withIntermediateDirectories: true
    )
    return try ActivityLog(path: path)
}

/// Read EnvironmentVariables from user LaunchAgent plist (doctor CLI context).
private func launchAgentEnvValue(_ key: String) -> String? {
    let plist = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/com.heald.daemon.plist")
    guard let data = try? Data(contentsOf: plist),
          let obj = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let env = obj["EnvironmentVariables"] as? [String: String] else {
        return nil
    }
    return env[key]
}

