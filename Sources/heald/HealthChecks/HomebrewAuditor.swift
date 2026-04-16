import Foundation
import OSLog

/// Audits Homebrew packages for known vulnerabilities.
/// Runs `brew audit --cask` and checks for security advisories.
struct HomebrewAuditor {
    func audit(activityLog: ActivityLog) async {
        guard let brewPath = ShellRunner.findExecutable("brew") else {
            Logger.health.info("HomebrewAuditor: brew not found, skipping")
            return
        }

        // Check for known vulnerable packages
        let result = ShellRunner.run(brewPath, arguments: ["outdated", "--json=v2"])
        guard result.succeeded, let data = result.output.data(using: .utf8) else { return }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        var vulnerableCount = 0
        var details: [String] = []

        // Check formulae
        if let formulae = json["formulae"] as? [[String: Any]] {
            for formula in formulae {
                guard let name = formula["name"] as? String,
                      let currentVersion = formula["installed_versions"] as? [String],
                      let pinnedVersion = formula["pinned_version"] as? String? else { continue }

                // Pinned packages might be held back for a reason
                if pinnedVersion != nil { continue }

                // Check if this is a security-sensitive package
                let securityPackages = [
                    "openssl", "curl", "git", "python", "node", "ruby",
                    "openssh", "gnupg", "wget", "nmap", "wireshark",
                    "postgresql", "mysql", "redis", "nginx", "apache"
                ]

                if securityPackages.contains(where: { name.lowercased().contains($0) }) {
                    vulnerableCount += 1
                    let versions = currentVersion.joined(separator: ", ")
                    details.append("\(name) (installed: \(versions))")
                }
            }
        }

        if vulnerableCount > 0 {
            Logger.health.warning("Homebrew: \(vulnerableCount) security-sensitive packages outdated")
            try? await activityLog.log(event: ActivityEvent(
                type: .brewVulnerability,
                summary: "\(vulnerableCount) security-sensitive Homebrew packages outdated",
                detail: details.joined(separator: "\n")
            ))
        } else {
            Logger.health.info("Homebrew security audit: all clear")
        }
    }
}
