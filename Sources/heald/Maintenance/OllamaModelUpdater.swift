import Foundation
import OSLog

/// Updates all installed Ollama models and optionally syncs GGUF files to LM Studio.
struct OllamaModelUpdater {

    // MARK: - Update All Models

    func updateAllModels(activityLog: ActivityLog) async throws {
        guard let ollama = ShellRunner.findExecutable("ollama") else {
            Logger.maintenance.info("Ollama not installed — skipping model updates")
            return
        }

        // List installed models
        let listResult = ShellRunner.run(ollama, arguments: ["list"])
        guard listResult.succeeded else {
            Logger.maintenance.info("Ollama not running — skipping model updates")
            return
        }

        let models = listResult.output
            .split(separator: "\n")
            .dropFirst() // header row
            .compactMap { $0.split(separator: " ").first.map(String.init) }
            .filter { !$0.isEmpty }

        guard !models.isEmpty else {
            Logger.maintenance.info("No Ollama models installed")
            return
        }

        Logger.maintenance.info("Updating \(models.count) Ollama models...")

        var updated = 0
        for model in models {
            Logger.maintenance.info("Pulling model: \(model)")
            let result = ShellRunner.run(ollama, arguments: ["pull", model])
            if result.succeeded { updated += 1 }
        }

        let summary = "Ollama: pulled \(updated)/\(models.count) models"

        try await activityLog.log(event: ActivityEvent(
            type: .modelUpdate,
            summary: summary,
            detail: models.joined(separator: ", ")
        ))

        Logger.maintenance.info("\(summary)")
    }

    // MARK: - LM Studio Sync

    func syncToLMStudio(activityLog: ActivityLog) async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let ollamaModelsPath = "\(home)/.ollama/models"
        let lmStudioPath = "\(home)/Library/Application Support/LM Studio/models"

        // Only sync if both directories exist
        guard FileManager.default.fileExists(atPath: ollamaModelsPath) else {
            Logger.maintenance.info("No Ollama models directory — skipping LM Studio sync")
            return
        }

        // Check if LM Studio is installed
        let lmStudioApp = "/Applications/LM Studio.app"
        guard FileManager.default.fileExists(atPath: lmStudioApp) else {
            Logger.maintenance.info("LM Studio not installed — skipping sync")
            return
        }

        // Create target directory
        try? FileManager.default.createDirectory(atPath: lmStudioPath, withIntermediateDirectories: true)

        // Find and copy GGUF files
        let findResult = ShellRunner.run(
            "/usr/bin/find",
            arguments: [ollamaModelsPath, "-name", "*.gguf", "-type", "f"]
        )

        guard findResult.succeeded else { return }

        let ggufFiles = findResult.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        guard !ggufFiles.isEmpty else {
            Logger.maintenance.info("No GGUF files found in Ollama models")
            return
        }

        var synced = 0
        for file in ggufFiles {
            let fileName = (file as NSString).lastPathComponent
            let destPath = "\(lmStudioPath)/\(fileName)"

            // Only copy if not already present
            if !FileManager.default.fileExists(atPath: destPath) {
                try? FileManager.default.copyItem(atPath: file, toPath: destPath)
                synced += 1
            }
        }

        if synced > 0 {
            let summary = "Synced \(synced) GGUF models to LM Studio"
            try await activityLog.log(event: ActivityEvent(
                type: .lmStudioSync,
                summary: summary
            ))
            Logger.maintenance.info("\(summary)")
        }
    }
}
