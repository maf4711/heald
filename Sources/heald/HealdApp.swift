import ArgumentParser
import Foundation
import ServiceLifecycle
import OSLog

@main
struct HealdApp: AsyncParsableCommand {
    static let version = "3.0.0"

    static let configuration = CommandConfiguration(
        commandName: "heald",
        abstract: "heald Enterprise — self-healing macOS daemon (no Meister dependency)",
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
        abstract: "Install + self-heal status"
    )

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("heald doctor v\(HealdApp.version) — Enterprise")
        print(String(repeating: "─", count: 48))
        print("Edition:    enterprise (native self-heal)")
        print("Meister:    not required / not linked")
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
        print("Self-heal:")
        let sh = dataDir.appendingPathComponent("self_heal.json")
        if let data = try? Data(contentsOf: sh),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("  status:     \(sh.path)")
            if let p = obj["ram_pressure"] { print("  ram_pressure: \(p)") }
            if let d = obj["disk_free_pct"] as? Double, d >= 0 {
                print(String(format: "  disk_free:   %.1f%%", d))
            }
            if let last = obj["last_actions"] as? [String: Any], !last.isEmpty {
                print("  last_actions: \(last.keys.sorted().joined(separator: ", "))")
            }
        } else {
            print("  status:     (waiting for first orchestrator tick)")
        }
        print("  loop:       detect → remediate → log → notify (every ~45s)")
        print("  schedule:   09:15 quick · Sun 10:30 deep · 02:00 benchmark")
        print(String(repeating: "─", count: 48))
        print("CLI: heald maintain | heal | autofix | storage | free | status")
    }
}

// MARK: - Status

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Self-heal status JSON + summary"
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

// MARK: - Maintain

struct MaintainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maintain",
        abstract: "Run native quick|deep maintenance now"
    )

    @Option(name: .shortAndLong, help: "quick|deep")
    var profile: String = "quick"

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/activity.ndjson").path
        try? FileManager.default.createDirectory(
            atPath: (logPath as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        let activityLog = try ActivityLog(path: logPath)
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

// MARK: - Heal / Autofix / Storage / Free

struct HealCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heal",
        abstract: "Run proactive healer now (symlinks, orphans, .DS_Store)"
    )
    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let log = try openActivityLog()
        print("heald heal (proactive)...")
        await ProactiveHealer().run(activityLog: log)
        print("done")
    }
}

struct AutofixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autofix",
        abstract: "Deterministic autofix (orphans, firewall, brew cleanup light)"
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
        abstract: "Safe-to-delete size report (read-only)"
    )
    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        StorageReport.printReport()
    }
}

struct FreeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "free",
        abstract: "Attempt RAM purge (sudo -n purge if available)"
    )
    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        let log = try openActivityLog()
        print("heald free...")
        await RAMPurge().purge(activityLog: log)
        print("done")
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
