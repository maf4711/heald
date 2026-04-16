import Foundation
import OSLog

/// Checks if the macOS firewall and stealth mode are enabled.
struct FirewallChecker {
    struct FirewallStatus: Sendable {
        let enabled: Bool
        let stealthMode: Bool
    }

    func check(activityLog: ActivityLog) async -> FirewallStatus {
        // Check firewall state via socketfilterfw
        let result = ShellRunner.run(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            arguments: ["--getglobalstate"]
        )

        var enabled = false
        if result.succeeded {
            enabled = result.output.contains("enabled")
        }

        // Check stealth mode
        let stealthResult = ShellRunner.run(
            "/usr/libexec/ApplicationFirewall/socketfilterfw",
            arguments: ["--getstealthmode"]
        )

        var stealthMode = false
        if stealthResult.succeeded {
            stealthMode = stealthResult.output.contains("enabled")
        }

        if !enabled {
            Logger.health.warning("macOS Firewall is DISABLED")
            try? await activityLog.log(event: ActivityEvent(
                type: .firewallDisabled,
                summary: "macOS firewall is disabled",
                detail: "Stealth mode: \(stealthMode ? "on" : "off")"
            ))
        } else {
            Logger.health.info("Firewall: enabled, stealth=\(stealthMode)")
        }

        return FirewallStatus(enabled: enabled, stealthMode: stealthMode)
    }
}
