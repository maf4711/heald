import Foundation

struct ActivityEvent: Identifiable, Codable {
    var id: String { "\(timestamp)-\(type)-\(summary.prefix(20))" }
    let timestamp: Date
    let machineId: String
    let type: String
    let summary: String
    let detail: String?
    let aiGenerated: Bool

    var category: EventCategory { EventCategory.from(type: type) }
    var icon: String { category.icon }

    var timeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var timestampFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }

    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: timestamp)
    }
}

enum EventCategory: String, CaseIterable {
    case healing, ai, health, maintenance, system, process

    var icon: String {
        switch self {
        case .healing: return "wand.and.stars"
        case .ai: return "brain"
        case .health: return "heart.text.clipboard"
        case .maintenance: return "wrench.and.screwdriver"
        case .system: return "gear"
        case .process: return "cpu"
        }
    }

    var label: String {
        switch self {
        case .healing: return "Healing"
        case .ai: return "AI"
        case .health: return "Health"
        case .maintenance: return "Maintenance"
        case .system: return "System"
        case .process: return "Process"
        }
    }

    static func from(type: String) -> EventCategory {
        switch type {
        case "healingAttempt", "healingSuccess", "healingFailed", "selfHealed",
             "dnsFlushed", "crashDetected":
            return .healing
        case "aiFixBlocked":
            return .ai
        case "diskWarning", "smartFailure", "swapSpike",
             "orphanedPlistFound", "brokenPlistFound":
            return .health
        case "brewUpgrade", "masUpdate", "cacheCleanup", "trashCleanup",
             "largeFileFound", "clamavScan", "modelUpdate", "spotlightFix",
             "periodicMaintenance", "maintenanceStarted", "maintenanceCompleted",
             "officeUpdate", "appMigration", "lmStudioSync":
            return .maintenance
        case "daemonStarted", "daemonStopped", "retentionPurge":
            return .system
        case "processKilled", "processRestarted":
            return .process
        default:
            return .system
        }
    }
}
