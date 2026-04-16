import Foundation
import OSLog

/// Checks XProtect status: version, signature age, and Remediator.
struct XProtectChecker {
    /// Warn if XProtect signatures are older than 14 days
    private let maxSignatureAgeDays = 14

    struct XProtectStatus: Sendable {
        let version: String?
        let signatureAgeDays: Int?
        let remediatorVersion: String?
    }

    func check(activityLog: ActivityLog) async -> XProtectStatus {
        // 1. XProtect version via pkgutil (faster than system_profiler)
        var version: String?
        let pkgResult = ShellRunner.run("/usr/sbin/pkgutil", arguments: [
            "--pkg-info", "com.apple.pkg.XProtectPlistConfigData"
        ])
        if pkgResult.succeeded {
            for line in pkgResult.output.split(separator: "\n") {
                if line.contains("version:") {
                    version = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
                }
            }
        }
        // Fallback package name
        if version == nil {
            let fallback = ShellRunner.run("/usr/sbin/pkgutil", arguments: [
                "--pkg-info", "com.apple.pkg.XProtectPayloads"
            ])
            if fallback.succeeded {
                for line in fallback.output.split(separator: "\n") {
                    if line.contains("version:") {
                        version = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }

        // 2. Signature age
        var signatureAgeDays: Int?
        let yaraPath = "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.yara"
        if FileManager.default.fileExists(atPath: yaraPath) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: yaraPath),
               let modDate = attrs[.modificationDate] as? Date {
                signatureAgeDays = Int(Date().timeIntervalSince(modDate) / 86400)
            }
        }

        if let age = signatureAgeDays, age > maxSignatureAgeDays {
            Logger.health.warning("XProtect signatures are \(age) days old (threshold: \(self.maxSignatureAgeDays))")
            try? await activityLog.log(event: ActivityEvent(
                type: .xprotectStale,
                summary: "XProtect signatures \(age) days old (threshold: \(maxSignatureAgeDays))",
                detail: "Version: \(version ?? "unknown")"
            ))
        }

        // 3. XProtect Remediator version
        var remediatorVersion: String?
        let remediatorPlist = "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist"
        if FileManager.default.fileExists(atPath: remediatorPlist) {
            let plistResult = ShellRunner.run("/usr/libexec/PlistBuddy", arguments: [
                "-c", "Print :CFBundleShortVersionString", remediatorPlist
            ])
            if plistResult.succeeded {
                remediatorVersion = plistResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        Logger.health.info("XProtect: v\(version ?? "?"), signatures \(signatureAgeDays ?? -1)d old, Remediator v\(remediatorVersion ?? "?")")

        return XProtectStatus(
            version: version,
            signatureAgeDays: signatureAgeDays,
            remediatorVersion: remediatorVersion
        )
    }
}
