import ArgumentParser
import Foundation
import ServiceLifecycle
import OSLog

@main
struct HealdApp: AsyncParsableCommand {
    static let version = "2.1.0"

    static let configuration = CommandConfiguration(
        commandName: "heald",
        abstract: "Self-healing macOS system daemon (Apple Intelligence on-device)",
        version: version,
        subcommands: [RunCommand.self, DoctorCommand.self],
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
        Logger.lifecycle.info("heald \(HealdApp.version) starting (Apple Intelligence)")

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
        abstract: "Check install health, LaunchAgent, and Apple Intelligence"
    )

    func run() async throws {
        // Line-buffer so doctor works when stdout is a pipe (non-TTY).
        setvbuf(stdout, nil, _IOLBF, 0)

        print("heald doctor v\(HealdApp.version)")
        print(String(repeating: "─", count: 48))

        let exe = CommandLine.arguments.first ?? "heald"
        print("Binary:     \(exe)")
        print("Version:    \(HealdApp.version)")

        // Avoid importing FoundationModels in this command path — availability
        // can block for a long time; daemon checks AI on its own tick.
        print("AI:         Apple Intelligence (checked by daemon at runtime)")
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

        // Meister batch-maintain handshake (v2.1)
        print(String(repeating: "─", count: 48))
        print("Meister bridge (batch-maintain):")
        let home = FileManager.default.homeDirectoryForCurrentUser
        let lastJSON = home.appendingPathComponent(".meister/last.json")
        let prefTwin = home.appendingPathComponent(".meister/preferred_twin")
        let bridgeView = home.appendingPathComponent(".heald/data/meister_bridge.json")
        let preferred = MeisterBridgeService.preferredMaintainCLI(preferredTwinPath: prefTwin)
        print("  Preferred CLI: \(preferred)")
        if let snap = MeisterBridgeService.readLastJSON(at: lastJSON) {
            let score = snap.score.map(String.init) ?? "?"
            let ageH = String(format: "%.1f", snap.ageSeconds / 3600)
            print("  last.json:     score=\(score) err=\(snap.err) warn=\(snap.warn) age=\(ageH)h twin=\(snap.twin ?? "?") v=\(snap.version ?? "?")")
        } else {
            print("  last.json:     missing — run meisterSiri --quick once")
        }
        if FileManager.default.fileExists(atPath: bridgeView.path) {
            print("  bridge view:   \(bridgeView.path)")
        }
        if ShellRunner.findExecutable("meisterSiri") != nil {
            print("  meisterSiri:   on PATH ✓")
        } else {
            print("  meisterSiri:   not found (brew install meister)")
        }
        if ShellRunner.findExecutable("meister") != nil {
            print("  meister:       on PATH ✓")
        } else {
            print("  meister:       not found")
        }

        print(String(repeating: "─", count: 48))
        print("Status: doctor OK — Meister bridge fields printed above")
    }
}
