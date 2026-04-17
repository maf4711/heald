import Foundation
import OSLog

/// Diagnoses and repairs Spotlight issues.
/// - Detects stuck mds process (CPU >30% and not actively indexing)
/// - Checks Spotlight index status per volume
/// - Validates Spotlight database size
struct SpotlightHealer {
    private let cpuThreshold = 30

    func check(activityLog: ActivityLog) async {
        // 1. mds CPU check
        let mdsCPU = getMdsCPU()
        if mdsCPU > cpuThreshold {
            Logger.health.warning("Spotlight mds CPU: \(mdsCPU)% (threshold: \(self.cpuThreshold)%)")

            // Check if actively indexing or stuck
            let indexStatus = ShellRunner.run("/usr/bin/mdutil", arguments: ["-s", "/"])
            let isIndexing = indexStatus.output.lowercased().contains("indexing enabled")

            if isIndexing {
                // Check mds process state
                let psResult = ShellRunner.run("/bin/ps", arguments: ["-p", getMdsPid(), "-o", "state="])
                let state = psResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

                if state != "R" && state != "R+" {
                    Logger.health.warning("mds appears stuck (state: \(state), CPU: \(mdsCPU)%)")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .spotlightStuck,
                        summary: "Spotlight mds stuck at \(mdsCPU)% CPU (state: \(state))",
                        detail: "mds may need restart (requires sudo)"
                    ))
                } else {
                    Logger.health.info("Spotlight actively indexing at \(mdsCPU)% CPU — normal")
                }
            }
        } else {
            Logger.health.debug("Spotlight mds CPU: \(mdsCPU)% (OK)")
        }

        // 2. Spotlight database size check
        let dbPaths = ["/.Spotlight-V100", "/private/var/db/Spotlight-V100"]
        for dbPath in dbPaths {
            guard FileManager.default.fileExists(atPath: dbPath) else { continue }
            let sizeResult = ShellRunner.run("/usr/bin/du", arguments: ["-sm", dbPath])
            if sizeResult.succeeded {
                let sizeMB = Int(sizeResult.output.split(separator: "\t").first ?? "0") ?? 0
                if sizeMB > 5120 {
                    Logger.health.warning("Spotlight DB unusually large: \(sizeMB) MB (>5 GB)")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .spotlightStuck,
                        summary: "Spotlight DB at \(sizeMB) MB — rebuild recommended"
                    ))
                }
            }
        }

        // 3. Broken Spotlight plugins
        let pluginDirs = ["/Library/Spotlight", "\(NSHomeDirectory())/Library/Spotlight"]
        var brokenPlugins = 0
        for dir in pluginDirs {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".mdimporter") {
                let plistPath = "\(dir)/\(item)/Contents/Info.plist"
                let validateResult = ShellRunner.run("/usr/bin/plutil", arguments: ["-lint", plistPath])
                if !validateResult.succeeded {
                    brokenPlugins += 1
                    Logger.health.warning("Broken Spotlight plugin: \(item)")
                }
            }
        }
        if brokenPlugins > 0 {
            try? await activityLog.log(event: ActivityEvent(
                type: .spotlightStuck,
                summary: "\(brokenPlugins) broken Spotlight plugins found"
            ))
        }
    }

    private func getMdsCPU() -> Int {
        let result = ShellRunner.run("/bin/ps", arguments: ["-eo", "%cpu,comm"])
        guard result.succeeded else { return 0 }

        var total: Double = 0
        for line in result.output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix("/mds") || trimmed.hasSuffix("mds_stores") {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if let cpu = parts.first.flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }) {
                    total += cpu
                }
            }
        }
        return Int(total)
    }

    private func getMdsPid() -> String {
        let result = ShellRunner.run("/usr/bin/pgrep", arguments: ["-x", "mds"])
        return result.output.split(separator: "\n").first.map(String.init) ?? "0"
    }
}
