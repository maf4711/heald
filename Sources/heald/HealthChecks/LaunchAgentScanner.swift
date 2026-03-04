import Foundation
import OSLog

/// HEAL-06, HEAL-07: Scans for orphaned and broken LaunchAgents.
struct LaunchAgentScanner {
    private let searchPaths = [
        "\(NSHomeDirectory())/Library/LaunchAgents",
        "/Library/LaunchAgents",
    ]

    func scan(activityLog: ActivityLog) async {
        for dir in searchPaths {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }

            for file in files where file.hasSuffix(".plist") {
                let plistPath = "\(dir)/\(file)"

                // HEAL-07: Validate plist syntax
                if !validatePlist(plistPath) {
                    Logger.health.warning("Broken plist: \(plistPath)")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .brokenPlistFound,
                        summary: "Broken plist: \(file)",
                        detail: plistPath
                    ))
                    continue
                }

                // HEAL-06: Check if referenced binary exists
                if let program = extractProgram(from: plistPath), !FileManager.default.fileExists(atPath: program) {
                    Logger.health.warning("Orphaned LaunchAgent: \(file) — binary missing: \(program)")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .orphanedPlistFound,
                        summary: "Orphaned LaunchAgent: \(file)",
                        detail: "Binary not found: \(program)",
                        beforeState: "plist exists at \(plistPath)",
                        afterState: "binary \(program) missing"
                    ))
                }
            }
        }
    }

    /// HEAL-07: Validate plist via plutil.
    private func validatePlist(_ path: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/plutil")
        task.arguments = ["-lint", path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Extract Program or ProgramArguments[0] from a plist.
    private func extractProgram(from path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }

        if let program = plist["Program"] as? String {
            return program
        }
        if let args = plist["ProgramArguments"] as? [String], let first = args.first {
            return first
        }
        return nil
    }
}
