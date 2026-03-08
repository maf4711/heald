import Foundation
import OSLog

// MARK: - Safety Blocklist

/// Blocks dangerous AI-generated commands before execution.
enum AISafetyBlocklist {
    private static let blockedPatterns: [String] = [
        "rm -rf /",
        "rm -rf /*",
        "mkfs",
        "dd if=",
        "chmod -R 777 /",
        "> /dev/sda",
        ":(){ :|:& };:",
        "mv / ",
        "wget.*|.*sh",
        "curl.*|.*sh",
        "launchctl remove com.apple",
        "killall Finder && killall Dock && killall SystemUIServer",
        "defaults delete /",
        "diskutil eraseDisk",
        "diskutil partitionDisk",
        "csrutil disable",
        "nvram boot-args",
    ]

    /// Returns true if the command is safe to execute.
    static func isSafe(_ command: String) -> Bool {
        let lower = command.lowercased()
        for pattern in blockedPatterns {
            if lower.contains(pattern.lowercased()) {
                Logger.ai.error("AI Safety: blocked command containing '\(pattern)'")
                return false
            }
        }
        return true
    }
}

// MARK: - Patch Archive

/// Archives AI-generated fixes for audit trail.
enum AIPatchArchive {
    private static let patchDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.heald/patches"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func save(moduleName: String, command: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let ts = formatter.string(from: Date())
        let filename = "\(moduleName)_\(ts).sh"
        let path = "\(patchDir)/\(filename)"

        let content = """
            #!/bin/bash
            # AI-Fix: \(moduleName) (\(ts))
            # Applied by heald SelfHealingRunner
            \(command)
            """

        try? content.write(toFile: path, atomically: true, encoding: .utf8)
        Logger.ai.info("Patch archived: \(filename)")
    }
}

// MARK: - Self-Healing Runner

/// Generic retry + AI analysis wrapper (adapted from meister2026.sh run_module_safe).
struct SelfHealingRunner {
    let ollamaClient: OllamaClient
    let activityLog: ActivityLog
    let maxRetries: Int = 2

    /// Run an operation with self-healing: on failure, ask Ollama for a fix, apply it, retry.
    func runSafe(name: String, _ operation: @Sendable () async throws -> Void) async {
        for attempt in 1...(maxRetries + 1) {
            do {
                try await operation()

                if attempt > 1 {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .selfHealed,
                        summary: "\(name) succeeded after \(attempt) attempts",
                        aiGenerated: true
                    ))
                    Logger.maintenance.info("\(name) self-healed after \(attempt) attempts")
                }
                return

            } catch {
                Logger.maintenance.error("\(name) failed (attempt \(attempt)/\(maxRetries + 1)): \(error)")

                if attempt > maxRetries {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .healingFailed,
                        summary: "\(name) failed after \(maxRetries + 1) attempts",
                        detail: error.localizedDescription
                    ))
                    break
                }

                // Ask Ollama for a fix
                guard await ollamaClient.isAvailable else {
                    Logger.maintenance.info("Ollama offline — no self-healing available for \(name)")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .healingFailed,
                        summary: "\(name) failed (Ollama offline)",
                        detail: error.localizedDescription
                    ))
                    break
                }

                Logger.maintenance.info("Analyzing \(name) failure with Ollama...")

                guard let fix = await ollamaClient.selfHealAnalyze(
                    moduleName: name,
                    error: error.localizedDescription
                ), fix != "NOFIX" else {
                    Logger.maintenance.info("Ollama: no fix available for \(name)")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .healingFailed,
                        summary: "Self-Heal: no fix for \(name)",
                        detail: error.localizedDescription,
                        aiGenerated: true
                    ))
                    break
                }

                // Safety check
                guard AISafetyBlocklist.isSafe(fix) else {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .aiFixBlocked,
                        summary: "Blocked dangerous AI fix for \(name)",
                        detail: fix,
                        aiGenerated: true
                    ))
                    Logger.ai.error("Blocked unsafe AI fix for \(name): \(fix.prefix(100))")
                    break
                }

                // Archive the patch
                AIPatchArchive.save(moduleName: name, command: fix)

                // Apply the fix
                Logger.maintenance.info("Applying AI fix for \(name)...")
                let result = ShellRunner.run("/bin/bash", arguments: ["-c", fix])

                if !result.succeeded {
                    Logger.maintenance.error("AI fix for \(name) failed: \(result.errorOutput.prefix(200))")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .healingFailed,
                        summary: "AI fix failed for \(name)",
                        detail: result.errorOutput,
                        aiGenerated: true
                    ))
                    break
                }

                // Retry after fix
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}
