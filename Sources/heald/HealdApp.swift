import ArgumentParser
import Foundation
import ServiceLifecycle
import OSLog
import FoundationModels

@main
struct HealdApp: AsyncParsableCommand {
    static let version = "2.0.0"

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
        print("heald doctor v\(HealdApp.version)")
        print(String(repeating: "─", count: 48))

        let exe = CommandLine.arguments.first ?? "heald"
        print("Binary:     \(exe)")
        print("Version:    \(HealdApp.version)")

        let aiStatus: String
        switch SystemLanguageModel.default.availability {
        case .available:
            aiStatus = "available (on-device)"
        default:
            aiStatus = "unavailable — enable Apple Intelligence in System Settings"
        }
        print("AI:         Apple Intelligence — \(aiStatus)")
        print("AI backend: FoundationModels (no Ollama)")

        let dataDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        let dataOK = FileManager.default.fileExists(atPath: dataDir.path)
        print("Data dir:   \(dataDir.path) \(dataOK ? "✓" : "(not created yet)")")

        let apiKey = ProcessInfo.processInfo.environment["HEALD_API_KEY"] ?? ""
        let apiURL = ProcessInfo.processInfo.environment["HEALD_API_URL"]
            ?? "https://heald.merados.com/api/ingest"
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

        print(String(repeating: "─", count: 48))
        if case .available = SystemLanguageModel.default.availability {
            print("Status: OK — local AI ready")
        } else {
            print("Status: degraded — rules-only healing until Apple Intelligence is available")
        }
    }
}
