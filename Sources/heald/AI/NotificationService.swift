import Foundation
import ServiceLifecycle
import OSLog

/// NOTF-01..04: macOS notifications + daily email report.
struct NotificationService: Service {
    let store: MetricsStore
    let activityLog: ActivityLog
    let ollamaClient: OllamaClient

    func run() async throws {
        while true {
            try await Task.sleep(for: .seconds(60))

            let now = Calendar.current.dateComponents([.hour, .minute], from: Date())

            // NOTF-02: Daily email at 18:00
            if now.hour == 18 && now.minute == 0 {
                await sendDailyReport()
            }
        }
    }

    /// NOTF-01: Send macOS notification for critical events.
    static func sendNotification(title: String, message: String) {
        let script = "display notification \"\(message.replacingOccurrences(of: "\"", with: "\\\""))\" with title \"\(title.replacingOccurrences(of: "\"", with: "\\\""))\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = Pipe()
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Logger.ai.error("Notification failed: \(error)")
        }
    }

    /// NOTF-02, NOTF-03, NOTF-04: Daily email with AI summary.
    private func sendDailyReport() async {
        let recipient = "foellmer@mac.com"

        // Read today's activity log
        let logPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/activity.ndjson").path

        guard let content = try? String(contentsOfFile: logPath, encoding: .utf8) else {
            Logger.ai.info("No activity log for daily report")
            return
        }

        // Get last 24h of events
        let lines = content.split(separator: "\n").suffix(100)
        let eventsText = lines.joined(separator: "\n")

        // NOTF-04: AI summary
        var summary = "heald Daily Report\n\n"
        if let aiSummary = await ollamaClient.generateDailySummary(events: eventsText) {
            summary += "AI Zusammenfassung:\n\(aiSummary)\n\n"
        }
        summary += "Letzte Events:\n\(eventsText)"

        // NOTF-03: Send via sendmail
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/sendmail")
        task.arguments = ["-t"]
        let pipe = Pipe()
        task.standardInput = pipe

        let email = """
            To: \(recipient)
            Subject: heald Daily Report - \(ISO8601DateFormatter().string(from: Date()))
            Content-Type: text/plain; charset=utf-8

            \(summary)
            """

        pipe.fileHandleForWriting.write(Data(email.utf8))
        pipe.fileHandleForWriting.closeFile()

        do {
            try task.run()
            task.waitUntilExit()
            Logger.ai.info("Daily report sent to \(recipient)")
        } catch {
            Logger.ai.error("Failed to send daily report: \(error)")
        }
    }
}
