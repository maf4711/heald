import Foundation
import OSLog

/// AI-01, AI-04, AI-05: Ollama integration with qwen3-coder:30b.
/// Falls back to rule-based decisions when Ollama is unavailable.
actor OllamaClient {
    private let baseURL: String
    private let model: String
    private(set) var isAvailable: Bool = false

    init(
        baseURL: String = ProcessInfo.processInfo.environment["OLLAMA_URL"] ?? "http://localhost:11434",
        model: String = "qwen3-coder:30b"
    ) {
        self.baseURL = baseURL
        self.model = model
    }

    /// Check if Ollama is reachable.
    func checkAvailability() async {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            isAvailable = false
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            isAvailable = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            isAvailable = false
        }

        Logger.ai.info("Ollama: \(self.isAvailable ? "online" : "offline") (\(self.model))")
    }

    /// AI-02: Ask Ollama whether a process should be killed.
    func shouldKillProcess(name: String, cpuPercent: Double, ramMB: Double, duration: TimeInterval) async -> AIDecision {
        guard isAvailable else { return .fallbackToRules }

        let prompt = """
            Du bist ein macOS System-Administrator. Ein Prozess verbraucht ueberdurchschnittlich viele Ressourcen.

            PROZESS: \(name)
            CPU: \(String(format: "%.1f", cpuPercent))%
            RAM: \(String(format: "%.0f", ramMB)) MB
            DAUER: \(Int(duration)) Sekunden

            Soll der Prozess beendet werden? Antworte NUR mit:
            KILL — wenn der Prozess beendet werden soll
            WAIT — wenn noch gewartet werden soll
            IGNORE — wenn der Prozess normal arbeitet

            Kein Markdown. Nur ein Wort.
            """

        guard let response = await query(prompt: prompt) else { return .fallbackToRules }

        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.contains("KILL") { return .kill }
        if trimmed.contains("WAIT") { return .wait }
        if trimmed.contains("IGNORE") { return .ignore }
        return .fallbackToRules
    }

    /// AI-03: Generate daily summary from activity log.
    func generateDailySummary(events: String) async -> String? {
        guard isAvailable else { return nil }

        let prompt = """
            Du bist ein macOS System-Bericht-Generator. Fasse die folgenden System-Events des Tages zusammen.
            Schreibe einen kurzen, klaren Bericht auf Deutsch (max 10 Saetze).

            EVENTS:
            \(events)

            ZUSAMMENFASSUNG:
            """

        return await query(prompt: prompt)
    }

    /// Low-level Ollama API call.
    private func query(prompt: String) async -> String? {
        guard let url = URL(string: "\(baseURL)/api/generate") else { return nil }

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.1, "num_predict": 512],
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let response = json["response"] as? String else { return nil }
            return response
        } catch {
            Logger.ai.error("Ollama query failed: \(error)")
            return nil
        }
    }
}

enum AIDecision: Sendable {
    case kill
    case wait
    case ignore
    case fallbackToRules
}
