import Foundation
import OSLog

/// Enterprise policy pack — `~/.heald/policy.json`
/// Consent: auto | ask | log
enum ConsentMode: String, Codable, Sendable {
    case auto  // remediate without prompt
    case ask   // notify only; wait for `heald approve <action>` or next auto after grace
    case log   // log only, never change system
}

/// Named presets for regulated deployments.
enum PolicyPreset: String, Codable, Sendable {
    case lab      // developer defaults
    case bank     // Deutsche Bank pilot-safe
    case standard // alias of lab
}

struct PolicyPack: Codable, Sendable {
    var schema: String = "heald.policy/v1"
    var edition: String = "enterprise"
    var preset: String = PolicyPreset.lab.rawValue
    var consent: ConsentMode = .auto

    // Feature toggles
    var selfHealEnabled: Bool = true
    var processKillEnabled: Bool = true
    var diskCleanupEnabled: Bool = true
    var ramPurgeEnabled: Bool = true
    var firewallEnforce: Bool = true
    var fileVaultWarn: Bool = true
    var crashLoopQuarantine: Bool = true
    var batteryGuardian: Bool = true
    var networkSelfHeal: Bool = true
    var safeSoftwareUpdate: Bool = false  // opt-in: security patches only
    var webhookEnabled: Bool = false
    var fleetAckEnabled: Bool = true

    // Phase A — bank / privacy / SIEM
    /// When false, CloudPusher is idle (also HEALD_CLOUD=0).
    var cloudEnabled: Bool = true
    /// Redact paths/emails/IPs on outbound cloud + SIEM events.
    var piiRedaction: Bool = true
    /// UDP syslog to SIEM (or set HEALD_SIEM_HOST).
    var siemSyslogEnabled: Bool = false
    var siemSyslogHost: String? = nil
    var siemSyslogPort: UInt16 = 514
    /// Prefer device token over shared API key for fleet auth messaging.
    var preferDeviceToken: Bool = true
    /// When true/nil, daemon polls /api/update (unless HEALD_AUTO_UPDATE=0). Optional for old policy.json.
    var autoUpdateEnabled: Bool? = true
    /// When true/nil, detect high load and apply boot-stampede heals.
    var performanceAutohealEnabled: Bool? = true
    /// Optional daily meisterSiri --auto (skip if binary missing). Bank preset turns this off.
    var meisterBridgeEnabled: Bool? = true

    // Thresholds
    var diskFreePctCritical: Double = 8
    var diskFreePctWarn: Double = 15
    var ramPressureMin: Int = 2
    var batteryHealthMinPct: Int = 80
    var batteryCycleWarn: Int = 800
    var crashLoopCount: Int = 5
    var crashLoopWindowSec: Int = 600

    // Integrations
    var slackWebhookURL: String? = nil
    var fleetIngestURL: String? = "https://heald.sh/api/ingest"
    var maintenanceWindowStartHour: Int = 2   // local hour for safe updates
    var maintenanceWindowEndHour: Int = 5

    static var policyURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/policy.json")
    }

    static func load() -> PolicyPack {
        let url = policyURL
        var p: PolicyPack
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(PolicyPack.self, from: data) {
            p = decoded
        } else {
            p = PolicyPack()
            p.save()
        }
        // Wave 2: MDM / Managed Preferences override local file (Jamf domain sh.heald)
        applyManagedOverrides(to: &p)
        return p
    }

    /// Merge keys from Managed Preferences domain `sh.heald` (and `com.heald.policy`).
    /// MDM wins over local policy.json for bank control.
    static func applyManagedOverrides(to p: inout PolicyPack) {
        let domains = ["sh.heald", "com.heald.policy"]
        for domain in domains {
            if let s = cfString("consent", domain: domain), let mode = ConsentMode(rawValue: s) {
                p.consent = mode
            }
            if let s = cfString("preset", domain: domain) {
                p.preset = s
            }
            if let b = cfBool("cloudEnabled", domain: domain) {
                p.cloudEnabled = b
            }
            if let b = cfBool("selfHealEnabled", domain: domain) {
                p.selfHealEnabled = b
            }
            if let b = cfBool("processKillEnabled", domain: domain) {
                p.processKillEnabled = b
            }
            if let b = cfBool("diskCleanupEnabled", domain: domain) {
                p.diskCleanupEnabled = b
            }
            if let b = cfBool("ramPurgeEnabled", domain: domain) {
                p.ramPurgeEnabled = b
            }
            if let b = cfBool("piiRedaction", domain: domain) {
                p.piiRedaction = b
            }
            if let b = cfBool("siemSyslogEnabled", domain: domain) {
                p.siemSyslogEnabled = b
            }
            if let s = cfString("siemSyslogHost", domain: domain) {
                p.siemSyslogHost = s
            }
            if let b = cfBool("autoUpdate", domain: domain) {
                p.autoUpdateEnabled = b
                if !b { setenv("HEALD_AUTO_UPDATE", "0", 1) }
            }
            if let b = cfBool("autoUpdateEnabled", domain: domain) {
                p.autoUpdateEnabled = b
                if !b { setenv("HEALD_AUTO_UPDATE", "0", 1) }
            }
        }
    }

    private static func cfString(_ key: String, domain: String) -> String? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? String
    }

    private static func cfBool(_ key: String, domain: String) -> Bool? {
        guard let v = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return nil }
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String {
            switch s.lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        }
        return nil
    }

    /// True if any managed preference domain is present.
    static func hasManagedPolicy() -> Bool {
        for domain in ["sh.heald", "com.heald.policy"] {
            if CFPreferencesCopyAppValue("consent" as CFString, domain as CFString) != nil
                || CFPreferencesCopyAppValue("preset" as CFString, domain as CFString) != nil {
                return true
            }
        }
        return false
    }

    /// Bank pilot preset — audit-first, no destructive defaults.
    static func bankPreset() -> PolicyPack {
        var p = PolicyPack()
        p.preset = PolicyPreset.bank.rawValue
        p.consent = .log
        p.selfHealEnabled = true          // detect + log still run
        p.processKillEnabled = false
        p.diskCleanupEnabled = false
        p.ramPurgeEnabled = false
        p.firewallEnforce = false         // warn via health checks only
        p.fileVaultWarn = true
        p.crashLoopQuarantine = false
        p.batteryGuardian = true
        p.networkSelfHeal = false
        p.safeSoftwareUpdate = false
        p.webhookEnabled = false
        p.fleetAckEnabled = true
        p.cloudEnabled = false            // no telemetry until approved
        p.piiRedaction = true
        p.siemSyslogEnabled = false
        p.preferDeviceToken = true
        // Distribution still allowed; cloud metrics stay off
        p.autoUpdateEnabled = true // fleet distribution on; cloud metrics still off
        p.meisterBridgeEnabled = false
        return p
    }

    static func labPreset() -> PolicyPack {
        var p = PolicyPack()
        p.preset = PolicyPreset.lab.rawValue
        p.consent = .auto
        p.cloudEnabled = true
        p.piiRedaction = true
        p.autoUpdateEnabled = true
        return p
    }

    func save() {
        let dir = Self.policyURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: Self.policyURL, options: .atomic)
        }
    }

    /// Whether destructive/remediation actions may run.
    func allowsRemediation() -> Bool {
        switch consent {
        case .auto: return true
        case .ask, .log: return false
        }
    }

    /// CPU / boot-stampede heals stay on even when bank consent=log.
    /// Toggle off with `performanceAutohealEnabled: false`.
    func allowsPerformanceRemediation() -> Bool {
        guard selfHealEnabled else { return false }
        if performanceAutohealEnabled == false { return false }
        return true
    }

    func allowsLog() -> Bool { true }

    /// Cloud push allowed (policy ∧ env).
    func allowsCloud() -> Bool {
        if ProcessInfo.processInfo.environment["HEALD_CLOUD"] == "0" { return false }
        return cloudEnabled
    }
}

/// Shared policy holder for services.
actor PolicyStore {
    static let shared = PolicyStore()
    private var pack: PolicyPack = .load()

    func current() -> PolicyPack { pack }

    func reload() {
        pack = .load()
        Logger.lifecycle.info("Policy reloaded: consent=\(self.pack.consent.rawValue) preset=\(self.pack.preset)")
    }

    func update(_ mutate: (inout PolicyPack) -> Void) {
        mutate(&pack)
        pack.save()
    }
}
