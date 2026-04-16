import Foundation

/// Combined security posture: FileVault, Firewall, Gatekeeper, SIP, XProtect.
struct SecuritySnapshot: Sendable {
    let fileVaultEnabled: Bool
    let firewallEnabled: Bool
    let firewallStealthMode: Bool
    let gatekeeperEnabled: Bool
    let sipEnabled: Bool
    let xprotectVersion: String?
    let xprotectSignatureAgeDays: Int?
    let xprotectRemediatorVersion: String?
    let timestamp: Date

    static let empty = SecuritySnapshot(
        fileVaultEnabled: false, firewallEnabled: false,
        firewallStealthMode: false, gatekeeperEnabled: false,
        sipEnabled: false, xprotectVersion: nil,
        xprotectSignatureAgeDays: nil, xprotectRemediatorVersion: nil,
        timestamp: .distantPast
    )

    var securityScore: Int {
        var score = 0
        if fileVaultEnabled { score += 1 }
        if firewallEnabled { score += 1 }
        if gatekeeperEnabled { score += 1 }
        if sipEnabled { score += 1 }
        return score
    }
}

struct PersistenceAuditEntry: Sendable {
    let plistName: String
    let label: String
    let binaryPath: String?
    let issues: [String]
}

struct GitRepoStatus: Sendable {
    let path: String
    let name: String
    let branch: String
    let dirtyFileCount: Int
    let unpushedCommitCount: Int
}

struct SSDWearSnapshot: Sendable {
    let percentageUsed: Int?       // NVMe percentage used (0-100+)
    let availableSpare: Int?       // NVMe available spare (0-100)
    let dataWrittenTB: Double?     // total host writes in TB
    let powerOnHours: Int?
    let estimatedLifeRemainingPercent: Int?
    let timestamp: Date

    static let empty = SSDWearSnapshot(
        percentageUsed: nil, availableSpare: nil, dataWrittenTB: nil,
        powerOnHours: nil, estimatedLifeRemainingPercent: nil,
        timestamp: .distantPast
    )
}

struct TimeMachineSnapshot: Sendable {
    let isConfigured: Bool
    let lastBackupDate: Date?
    let oldestBackupDate: Date?
    let backupSizeGB: Double?
    let destinationName: String?
    let autoBackupEnabled: Bool
    let hoursSinceLastBackup: Double?
    let timestamp: Date

    static let empty = TimeMachineSnapshot(
        isConfigured: false, lastBackupDate: nil, oldestBackupDate: nil,
        backupSizeGB: nil, destinationName: nil, autoBackupEnabled: false,
        hoursSinceLastBackup: nil, timestamp: .distantPast
    )
}

struct LoginItemEntry: Sendable {
    let name: String
    let path: String?
    let isHidden: Bool
}

struct LoginItemsSnapshot: Sendable {
    let items: [LoginItemEntry]
    let timestamp: Date

    static let empty = LoginItemsSnapshot(items: [], timestamp: .distantPast)
}

struct MemoryLeakSuspect: Sendable {
    let pid: Int32
    let name: String
    let currentMB: Double
    let growthMB: Double          // growth over tracking window
    let trackingMinutes: Double
    let growthRateMBPerHour: Double
}

struct MemoryLeakSnapshot: Sendable {
    let suspects: [MemoryLeakSuspect]
    let timestamp: Date

    static let empty = MemoryLeakSnapshot(suspects: [], timestamp: .distantPast)
}

struct FocusSnapshot: Sendable {
    let isActive: Bool
    let modeName: String?     // "Do Not Disturb", "Work", etc.
    let timestamp: Date

    static let empty = FocusSnapshot(isActive: false, modeName: nil, timestamp: .distantPast)
}
