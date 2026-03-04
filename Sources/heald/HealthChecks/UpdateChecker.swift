import Foundation
import OSLog

/// HLTH-01, HLTH-02: Checks Homebrew packages and macOS updates.
struct UpdateChecker {
    struct UpdateReport: Sendable {
        let outdatedBrewPackages: [String]
        let macOSUpdateAvailable: Bool
    }

    func check() -> UpdateReport {
        let brewOutdated = checkBrewOutdated()
        let macOSUpdate = checkMacOSUpdate()

        if !brewOutdated.isEmpty {
            Logger.health.info("Outdated Homebrew packages: \(brewOutdated.joined(separator: ", "))")
        }
        if macOSUpdate {
            Logger.health.info("macOS update available")
        }

        return UpdateReport(outdatedBrewPackages: brewOutdated, macOSUpdateAvailable: macOSUpdate)
    }

    /// HLTH-01: Check brew outdated
    private func checkBrewOutdated() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/brew")
        task.arguments = ["outdated", "--quiet"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            // brew not installed or not at this path
            return []
        }

        guard task.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return [] }

        return output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// HLTH-02: Check softwareupdate
    private func checkMacOSUpdate() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        task.arguments = ["-l"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.environment = ["COMMAND_LINE_INSTALL": "1"]

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return false }

        return !output.contains("No new software available")
    }
}
