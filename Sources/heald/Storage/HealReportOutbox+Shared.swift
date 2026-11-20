import Foundation
import HealdCore

extension HealReportOutbox {
    /// Daemon outbox: ~/.heald/data/heal_reports.ndjson + heal_report_cursor.
    static let shared = HealReportOutbox(
        directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".heald/data")
    )
}
