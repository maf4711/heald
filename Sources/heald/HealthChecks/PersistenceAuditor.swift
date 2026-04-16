import Foundation
import OSLog

/// Audits LaunchAgents/Daemons for suspicious persistence mechanisms.
/// Goes beyond the existing LaunchAgentScanner by checking for:
/// - Binaries in /tmp or hidden folders
/// - Download+execute patterns (curl|sh, wget|sh, base64 decode)
/// - Cryptominer references
/// - Unsigned binaries
/// - Persistent + KeepAlive from unknown sources
struct PersistenceAuditor {
    private let knownSafePatterns = [
        "com.apple.", "com.google.keystone", "com.microsoft", "com.docker",
        "com.parallels", "com.adobe", "com.spotify", "com.dropbox",
        "com.1password", "com.jetbrains", "homebrew", "com.heald",
        "com.valvesoftware", "com.nordvpn", "com.ollama"
    ]

    private let searchPaths = [
        "\(NSHomeDirectory())/Library/LaunchAgents",
        "/Library/LaunchAgents",
        "/Library/LaunchDaemons",
    ]

    func audit(activityLog: ActivityLog) async -> [PersistenceAuditEntry] {
        var findings: [PersistenceAuditEntry] = []

        for dir in searchPaths {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }

            for file in files where file.hasSuffix(".plist") {
                let path = "\(dir)/\(file)"
                guard let data = FileManager.default.contents(atPath: path),
                      let plist = try? PropertyListSerialization.propertyList(
                        from: data, options: [], format: nil
                      ) as? [String: Any] else { continue }

                let label = plist["Label"] as? String ?? file
                let program = extractProgram(from: plist)

                // Skip known safe
                if knownSafePatterns.contains(where: { label.contains($0) }) { continue }

                var issues: [String] = []

                // Check 1: Binary exists?
                if let prog = program, !FileManager.default.fileExists(atPath: prog) {
                    issues.append("Binary missing: \(prog)")
                }

                // Check 2: Binary in suspicious location?
                if let prog = program {
                    if prog.hasPrefix("/tmp/") || prog.hasPrefix("/var/tmp/") || prog.hasPrefix("/private/tmp/") {
                        issues.append("Binary in /tmp (suspicious)")
                    }
                    let home = NSHomeDirectory()
                    if prog.hasPrefix("\(home)/.") {
                        let knownHidden = [".claude", ".ollama", ".nvm", ".npm", ".cargo", ".rustup", ".docker"]
                        if !knownHidden.contains(where: { prog.contains("/\($0)/") }) {
                            issues.append("Binary in hidden folder")
                        }
                    }
                }

                // Check 3: RunAtLoad + KeepAlive (persistent daemon)
                let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
                let keepAlive = plist["KeepAlive"] as? Bool ?? false
                if runAtLoad && keepAlive {
                    issues.append("RunAtLoad+KeepAlive (highly persistent)")
                }

                // Check 4: Suspicious content patterns
                let content = String(data: data, encoding: .utf8) ?? ""
                if content.range(of: "curl.*\\|.*sh|wget.*\\|.*sh|base64.*decode", options: .regularExpression) != nil {
                    issues.append("SUSPICIOUS: download+execute pattern")
                }
                let lowerContent = content.lowercased()
                if lowerContent.contains("cryptominer") || lowerContent.contains("xmrig") ||
                   lowerContent.contains("coinhive") || lowerContent.contains("minergate") {
                    issues.append("SUSPICIOUS: cryptominer reference")
                }

                // Check 5: Code signing
                if let prog = program, FileManager.default.fileExists(atPath: prog) {
                    let signResult = ShellRunner.run("/usr/bin/codesign", arguments: ["-v", prog])
                    if !signResult.succeeded {
                        issues.append("Binary not code-signed")
                    }
                }

                if !issues.isEmpty {
                    findings.append(PersistenceAuditEntry(
                        plistName: file, label: label,
                        binaryPath: program, issues: issues
                    ))

                    Logger.health.warning("Persistence audit: \(file) — \(issues.joined(separator: ", "))")
                    try? await activityLog.log(event: ActivityEvent(
                        type: .suspiciousPersistence,
                        summary: "Suspicious LaunchAgent: \(file)",
                        detail: "Label: \(label)\nBinary: \(program ?? "?")\nIssues: \(issues.joined(separator: ", "))"
                    ))
                }
            }
        }

        Logger.health.info("Persistence audit: \(findings.count) suspicious entries found")
        return findings
    }

    private func extractProgram(from plist: [String: Any]) -> String? {
        if let program = plist["Program"] as? String { return program }
        if let args = plist["ProgramArguments"] as? [String], let first = args.first { return first }
        return nil
    }
}
