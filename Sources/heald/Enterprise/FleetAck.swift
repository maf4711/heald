import Foundation
import OSLog

/// Fleet ACK: local remediation records only (`fleet_ack.ndjson`). Nothing leaves the device here.
enum FleetAck {
    static func record(
        action: String,
        result: String,
        detail: String? = nil
    ) async {
        let policy = await PolicyStore.shared.current()
        guard policy.fleetAckEnabled else { return }

        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let event: [String: Any] = [
            "schema": "heald.fleet_ack/v1",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "host": host,
            "action": action,
            "result": result,
            "detail": detail as Any,
            "edition": "enterprise",
        ]

        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("fleet_ack.ndjson")
        if let data = try? JSONSerialization.data(withJSONObject: event),
           var line = String(data: data, encoding: .utf8) {
            line += "\n"
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: file, atomically: true, encoding: .utf8)
            }
        }
        // Cloud delivery moved to heal reports (HealReportOutbox → CloudPusher, gated by allowsCloud()).
    }
}
