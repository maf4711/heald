import Foundation
import OSLog

/// SOC-lite: Slack (or any) incoming webhook for enterprise events.
actor WebhookNotifier {
    static let shared = WebhookNotifier()

    func emit(title: String, text: String, severity: String = "info") async {
        let policy = await PolicyStore.shared.current()
        guard policy.webhookEnabled, let urlStr = policy.slackWebhookURL,
              let url = URL(string: urlStr), !urlStr.isEmpty else { return }

        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let payload: [String: Any] = [
            "text": "[\(severity.uppercased())] heald@\(host): *\(title)*\n\(text)",
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 8

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            Logger.lifecycle.debug("Webhook POST \(code)")
        } catch {
            Logger.lifecycle.warning("Webhook failed: \(error.localizedDescription)")
        }
    }
}
