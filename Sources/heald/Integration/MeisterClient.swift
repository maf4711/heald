import Foundation
import OSLog

/// Facade over the Meister twin CLIs (`meisterSiri` preferred, `meister` fallback).
/// heald observes continuously; Meister owns the battle-tested batch-maintain modules.
enum MeisterClient {
    enum Profile: String, CaseIterable, Sendable {
        case quick
        case auto
        case deep
        case all
    }

    enum Tool: String, CaseIterable, Sendable {
        case doctor
        case heal
        case autofix
        case storage
        case score
        case report
        case free
        case why
        case twinsBench = "twins-bench"
        case today
        case privacy
        case contactsDoctor = "contacts-doctor"
    }

    struct RunResult: Sendable {
        let executable: String
        let arguments: [String]
        let exitCode: Int32
        let stdout: String
        let stderr: String
        let durationMs: Int
        var succeeded: Bool { exitCode == 0 || exitCode == 1 } // 1 = meister found issues but ran
    }

    // MARK: - Resolve CLI

    /// Preferred twin: `~/.meister/preferred_twin` then meisterSiri then meister.
    static func preferredExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let prefURL = home.appendingPathComponent(".meister/preferred_twin")
        if let raw = try? String(contentsOf: prefURL, encoding: .utf8) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "meister" || t == "meisterSiri", let p = ShellRunner.findExecutable(t) {
                return p
            }
        }
        return ShellRunner.findExecutable("meisterSiri")
            ?? ShellRunner.findExecutable("meister")
    }

    static var isInstalled: Bool { preferredExecutable() != nil }

    // MARK: - High-level ops

    /// Full maintenance profile (`--quick` / `--auto` / `--deep` / `-a`).
    static func maintain(
        profile: Profile = .quick,
        dryRun: Bool = false,
        quiet: Bool = true
    ) -> RunResult {
        var args: [String] = []
        switch profile {
        case .quick: args.append("--quick")
        case .auto: args.append("--auto")
        case .deep: args.append("--deep")
        case .all: args.append("-a")
        }
        if dryRun { args.append("-n") }
        if quiet { args.append("-q") }
        return run(arguments: args, label: "maintain-\(profile.rawValue)")
    }

    /// Named tool surface (maps to meister subcommands).
    static func tool(_ tool: Tool, extraArgs: [String] = []) -> RunResult {
        let args: [String]
        switch tool {
        case .doctor:
            args = ["doctor"] + extraArgs
        case .heal:
            args = ["heal"] + extraArgs
        case .autofix:
            args = ["autofix"] + extraArgs
        case .storage:
            args = ["storage"] + extraArgs
        case .score:
            args = ["score"] + extraArgs
        case .report:
            args = ["report"] + extraArgs
        case .free:
            args = ["free"] + extraArgs
        case .why:
            args = ["why"] + (extraArgs.isEmpty ? ["profile"] : extraArgs)
        case .twinsBench:
            args = ["twins-bench"] + extraArgs
        case .today:
            args = ["today"] + extraArgs
        case .privacy:
            args = ["privacy"] + extraArgs
        case .contactsDoctor:
            args = ["contacts", "doctor"] + extraArgs
        }
        return run(arguments: args, label: tool.rawValue)
    }

    /// Passthrough any argv to the preferred twin.
    static func passthrough(_ arguments: [String]) -> RunResult {
        run(arguments: arguments, label: "passthrough")
    }

    // MARK: - Core runner

    static func run(arguments: [String], label: String = "meister") -> RunResult {
        let start = Date()
        guard let exe = preferredExecutable() else {
            Logger.maintenance.error("MeisterClient[\(label)]: no meister/meisterSiri on PATH")
            return RunResult(
                executable: "",
                arguments: arguments,
                exitCode: 127,
                stdout: "",
                stderr: "meister/meisterSiri not found — brew install meister",
                durationMs: 0
            )
        }

        Logger.maintenance.info("MeisterClient[\(label)]: \(exe) \(arguments.joined(separator: " "))")
        let shell = ShellRunner.run(exe, arguments: arguments)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        return RunResult(
            executable: exe,
            arguments: arguments,
            exitCode: shell.exitCode,
            stdout: shell.output,
            stderr: shell.errorOutput,
            durationMs: ms
        )
    }

    // MARK: - last.json snapshot (read)

    static func readLastJSON() -> MeisterBridgeService.MeisterLastSnapshot? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".meister/last.json")
        return MeisterBridgeService.readLastJSON(at: url)
    }
}
