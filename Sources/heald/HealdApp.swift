import ArgumentParser
import Foundation
import ServiceLifecycle
import OSLog

@main
struct HealdApp: AsyncParsableCommand {
    static let version = "2.2.0"

    static let configuration = CommandConfiguration(
        commandName: "heald",
        abstract: "Self-healing macOS daemon + Meister batch-maintain integration",
        version: version,
        subcommands: [
            RunCommand.self,
            DoctorCommand.self,
            MaintainCommand.self,
            StatusCommand.self,
            MeisterCommand.self,
            HealCommand.self,
            AutofixCommand.self,
            StorageCommand.self,
            ScoreCommand.self,
            TwinsBenchCommand.self,
            WhyCommand.self,
        ],
        defaultSubcommand: RunCommand.self
    )
}

// MARK: - Run (daemon)

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the heald daemon (default)"
    )

    func run() async throws {
        Logger.lifecycle.info("heald \(HealdApp.version) starting (Meister integrated)")

        let store = MetricsStore()
        let service = HealdService(store: store)
        let serviceGroup = ServiceGroup(
            services: [service],
            gracefulShutdownSignals: [.sigterm, .sigint],
            logger: .init(label: "com.heald.daemon")
        )

        try await serviceGroup.run()
        Logger.lifecycle.info("heald stopped cleanly")
    }
}

// MARK: - Doctor

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Install health, LaunchAgent, Meister bridge"
    )

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)

        print("heald doctor v\(HealdApp.version)")
        print(String(repeating: "─", count: 48))

        let exe = CommandLine.arguments.first ?? "heald"
        print("Binary:     \(exe)")
        print("Version:    \(HealdApp.version)")
        print("AI:         Apple Intelligence (daemon runtime)")
        print("AI backend: FoundationModels (no Ollama)")

        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        let dataOK = FileManager.default.fileExists(atPath: dataDir.path)
        print("Data dir:   \(dataDir.path) \(dataOK ? "✓" : "(not created yet)")")

        let apiKey = ProcessInfo.processInfo.environment["HEALD_API_KEY"] ?? ""
        let apiURL = ProcessInfo.processInfo.environment["HEALD_API_URL"]
            ?? "https://heald.sh/api/ingest"
        print("API URL:    \(apiURL)")
        print("API key:    \(apiKey.isEmpty ? "not set (cloud push disabled)" : "set (\(apiKey.count) chars)")")

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

        printMeisterSection()
        print(String(repeating: "─", count: 48))
        print("Status: doctor OK — use `heald maintain` for Meister batch jobs")
    }
}

// MARK: - Status (Meister handshake)

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Meister last.json + preferred twin + bridge view"
    )

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        print("heald status v\(HealdApp.version)")
        printMeisterSection()
    }
}

// MARK: - Maintain (Meister profiles)

struct MaintainCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "maintain",
        abstract: "Run Meister batch-maintain (quick|auto|deep|all)"
    )

    @Option(name: .shortAndLong, help: "Profile: quick|auto|deep|all (default: quick)")
    var profile: String = "quick"

    @Flag(name: .customLong("dry-run"), help: "Dry-run (-n)")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Quiet (-q)")
    var quiet: Bool = false

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard MeisterClient.isInstalled else {
            print("ERROR: meister/meisterSiri not on PATH — brew install meister")
            throw ExitCode(127)
        }
        let p: MeisterClient.Profile
        switch profile.lowercased() {
        case "quick": p = .quick
        case "auto": p = .auto
        case "deep": p = .deep
        case "all", "a": p = .all
        default:
            print("Unknown profile '\(profile)' — use quick|auto|deep|all")
            throw ExitCode(2)
        }
        print("heald maintain → Meister --\(p.rawValue)\(dryRun ? " -n" : "")...")
        let result = MeisterClient.maintain(profile: p, dryRun: dryRun, quiet: quiet)
        if !result.stdout.isEmpty { print(result.stdout) }
        if !result.stderr.isEmpty { fputs(result.stderr, stderr) }
        print("exit \(result.exitCode) in \(result.durationMs)ms via \(result.executable)")
        throw ExitCode(result.exitCode == 0 ? 0 : (result.exitCode == 1 ? 1 : 1))
    }
}

// MARK: - Meister passthrough + tools

struct MeisterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meister",
        abstract: "Pass arguments through to preferred Meister twin",
        discussion: "Example: heald meister doctor --json · heald meister storage"
    )

    @Argument(parsing: .captureForPassthrough, help: "Args forwarded to meisterSiri/meister")
    var args: [String] = []

    func run() async throws {
        setvbuf(stdout, nil, _IOLBF, 0)
        guard MeisterClient.isInstalled else {
            print("ERROR: meister/meisterSiri not on PATH")
            throw ExitCode(127)
        }
        if args.isEmpty {
            print("Usage: heald meister <meister-args...>")
            print("  heald meister doctor --json")
            print("  heald meister --quick -n")
            print("  heald meister storage")
            throw ExitCode(2)
        }
        let result = MeisterClient.passthrough(args)
        if !result.stdout.isEmpty { print(result.stdout, terminator: "") }
        if !result.stderr.isEmpty { fputs(result.stderr, stderr) }
        throw ExitCode(result.exitCode == 0 ? 0 : 1)
    }
}

// Thin wrappers for common Meister tools

struct HealCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "heal",
        abstract: "Meister proactive healer (broken symlinks, orphans, …)"
    )
    @Flag(name: .customLong("dry-run"), help: "Dry-run")
    var dryRun: Bool = false
    func run() async throws {
        try runTool(.heal, extra: dryRun ? ["--dry-run"] : [])
    }
}

struct AutofixCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "autofix",
        abstract: "Meister deterministic autofix catalog"
    )
    func run() async throws { try runTool(.autofix) }
}

struct StorageCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "storage",
        abstract: "Meister storage candidates (DerivedData, caches, …)"
    )
    func run() async throws { try runTool(.storage) }
}

struct ScoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score",
        abstract: "Meister maintenance score history"
    )
    func run() async throws { try runTool(.score) }
}

struct TwinsBenchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "twins-bench",
        abstract: "Benchmark meister (Ollama) vs meisterSiri (Apple Intelligence)"
    )
    @Flag(name: .customLong("quick"), help: "Skip full dry-run")
    var quick: Bool = false
    @Flag(name: .customLong("json"), help: "JSON only")
    var json: Bool = false
    func run() async throws {
        var extra: [String] = []
        if quick { extra.append("--quick") }
        if json { extra.append("--json") }
        try runTool(.twinsBench, extra: extra)
    }
}

struct WhyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "why",
        abstract: "Meister why <module|profile|warn>"
    )
    @Argument(help: "What to explain (default: profile)")
    var query: String?
    func run() async throws {
        try runTool(.why, extra: [query ?? "profile"])
    }
}

// MARK: - Shared helpers

private func runTool(_ tool: MeisterClient.Tool, extra: [String] = []) throws {
    setvbuf(stdout, nil, _IOLBF, 0)
    guard MeisterClient.isInstalled else {
        print("ERROR: meister/meisterSiri not on PATH — brew install meister")
        throw ExitCode(127)
    }
    let result = MeisterClient.tool(tool, extraArgs: extra)
    if !result.stdout.isEmpty { print(result.stdout, terminator: result.stdout.hasSuffix("\n") ? "" : "\n") }
    if !result.stderr.isEmpty { fputs(result.stderr, stderr) }
    throw ExitCode(result.exitCode == 0 ? 0 : 1)
}

private func printMeisterSection() {
    print(String(repeating: "─", count: 48))
    print("Meister integration (batch-maintain):")
    if let exe = MeisterClient.preferredExecutable() {
        print("  CLI:          \(exe)")
    } else {
        print("  CLI:          NOT FOUND — brew install meister")
    }
    let prefURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".meister/preferred_twin")
    let preferred = MeisterBridgeService.preferredMaintainCLI(preferredTwinPath: prefURL)
    print("  Preferred:    \(preferred)")
    if let snap = MeisterClient.readLastJSON() {
        let score = snap.score.map(String.init) ?? "?"
        let ageH = String(format: "%.1f", snap.ageSeconds / 3600)
        print("  last.json:    score=\(score) err=\(snap.err) warn=\(snap.warn) age=\(ageH)h twin=\(snap.twin ?? "?") v=\(snap.version ?? "?")")
    } else {
        print("  last.json:    missing — run: heald maintain --profile quick")
    }
    let bridgeView = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".heald/data/meister_bridge.json")
    if FileManager.default.fileExists(atPath: bridgeView.path) {
        print("  bridge view:  \(bridgeView.path)")
    }
    print("  Commands:     heald maintain | heal | autofix | storage | score | twins-bench")
    print("  Passthrough:  heald meister <args…>")
    print("  Schedule:     daily 09:15 --quick · Sun 10:30 --deep (daemon)")
}
