import Foundation
import OSLog

/// Audits macOS TCC (Transparency, Consent, Control) privacy permissions.
/// Detects orphaned permissions for uninstalled apps.
struct TCCAuditor {
    private let criticalServices: [(service: String, name: String)] = [
        ("kTCCServiceAccessibility", "Accessibility"),
        ("kTCCServiceSystemPolicyAllFiles", "Full Disk Access"),
        ("kTCCServiceScreenCapture", "Screen Recording"),
        ("kTCCServiceMicrophone", "Microphone"),
        ("kTCCServiceCamera", "Camera"),
        ("kTCCServiceSystemPolicySysAdminFiles", "System Admin Files"),
        ("kTCCServiceAppleEvents", "Apple Events"),
    ]

    struct TCCFinding: Sendable {
        let service: String
        let app: String
        let isOrphaned: Bool
    }

    func audit(activityLog: ActivityLog) async -> [TCCFinding] {
        let tccPath = "\(NSHomeDirectory())/Library/Application Support/com.apple.TCC/TCC.db"
        guard FileManager.default.fileExists(atPath: tccPath) else {
            Logger.health.info("TCC audit: database not accessible")
            return []
        }

        var findings: [TCCFinding] = []

        for (service, name) in criticalServices {
            let result = ShellRunner.run("/usr/bin/sqlite3", arguments: [
                tccPath,
                "SELECT client FROM access WHERE service='\(service)' AND auth_value=2;"
            ])
            guard result.succeeded else { continue }

            let apps = result.output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
            if apps.isEmpty { continue }

            Logger.health.info("TCC \(name): \(apps.count) apps authorized")

            for app in apps {
                let orphaned = isAppOrphaned(app)
                if orphaned {
                    Logger.health.warning("TCC orphaned: \(app) has \(name) permission but is not installed")
                    findings.append(TCCFinding(service: name, app: app, isOrphaned: true))
                }
            }
        }

        let orphanCount = findings.filter(\.isOrphaned).count
        if orphanCount > 0 {
            try? await activityLog.log(event: ActivityEvent(
                type: .tccOrphanedPermission,
                summary: "\(orphanCount) orphaned TCC permissions found",
                detail: findings.filter(\.isOrphaned).map { "\($0.app): \($0.service)" }.joined(separator: "\n")
            ))
        }

        Logger.health.info("TCC audit: \(orphanCount) orphaned permissions")
        return findings
    }

    private func isAppOrphaned(_ app: String) -> Bool {
        // If it's a file path, check if it exists
        if app.hasPrefix("/") {
            return !FileManager.default.fileExists(atPath: app)
        }

        // If it's a bundle ID (com.xxx.yyy), check via mdfind
        if app.contains(".") {
            let result = ShellRunner.run("/usr/bin/mdfind", arguments: [
                "kMDItemCFBundleIdentifier == '\(app)'"
            ])
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return false
    }
}
