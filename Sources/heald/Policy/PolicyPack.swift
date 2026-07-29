import Foundation
import OSLog

/// Enterprise policy pack — `~/.heald/policy.json`
/// Consent: auto | ask | log
enum ConsentMode: String, Codable, Sendable {
    case auto  // remediate without prompt
    case ask   // notify only; wait for `heald approve <action>` or next auto after grace
    case log   // log only, never change system
}

struct PolicyPack: Codable, Sendable {
    var schema: String = "heald.policy/v1"
    var edition: String = "enterprise"
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
        if let data = try? Data(contentsOf: url),
           let p = try? JSONDecoder().decode(PolicyPack.self, from: data) {
            return p
        }
        let p = PolicyPack()
        p.save()
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

    func allowsLog() -> Bool { true }
}

/// Shared policy holder for services.
actor PolicyStore {
    static let shared = PolicyStore()
    private var pack: PolicyPack = .load()

    func current() -> PolicyPack { pack }

    func reload() {
        pack = .load()
        Logger.lifecycle.info("Policy reloaded: consent=\(self.pack.consent.rawValue)")
    }

    func update(_ mutate: (inout PolicyPack) -> Void) {
        mutate(&pack)
        pack.save()
    }
}
