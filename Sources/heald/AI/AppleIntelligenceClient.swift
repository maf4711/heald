import Foundation
import OSLog
import FoundationModels
import HealdCore

/// On-device AI via Apple Intelligence (FoundationModels) — same backend as meisterSiri.
/// No Ollama, no network model server. Falls back to rules when unavailable.
actor AppleIntelligenceClient {
    private(set) var isAvailable: Bool = false

    /// Probe SystemLanguageModel availability (Apple Intelligence enabled + model ready).
    func checkAvailability() async {
        switch SystemLanguageModel.default.availability {
        case .available:
            isAvailable = true
        default:
            isAvailable = false
        }
        Logger.ai.info("Apple Intelligence: \(self.isAvailable ? "available" : "unavailable")")
    }

    /// Whether a high-resource process should be killed.
    func shouldKillProcess(
        name: String,
        cpuPercent: Double,
        ramMB: Double,
        duration: TimeInterval
    ) async -> AIDecision {
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

    /// Natural-language daily summary for email report (German).
    func generateDailySummary(events: String) async -> String? {
        guard isAvailable else { return nil }

        let clipped = String(events.suffix(6000))
        let prompt = """
            Du bist ein macOS System-Bericht-Generator. Fasse die folgenden System-Events des Tages zusammen.
            Schreibe einen kurzen, klaren Bericht auf Deutsch (max 10 Saetze).

            EVENTS:
            \(clipped)

            ZUSAMMENFASSUNG:
            """

        return await query(prompt: prompt)
    }

    /// Advisor verdict for a rule-triggered self-heal action, as JSON for `AutohealAdvisor.parse`.
    /// Guided generation restricts action/recommendation to the fixed catalog. Advice only.
    func adviseHeal(action: String, reason: String, context: String) async -> String? {
        guard isAvailable else { return nil }

        let instructions = """
            You advise a macOS self-heal daemon. The rules already decided to run one action.
            You may only confirm it (proceed), postpone it (defer) or advise against it (skip).
            Never suggest commands. Answer for exactly the action given.
            """
        let prompt = String("""
            ACTION: \(action)
            TRIGGER: \(reason)
            CONTEXT: \(context)
            """.prefix(AutohealAdvisor.maxInputChars))

        do {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
            let response = try await session.respond(to: prompt, generating: HealAdvice.self)
            let data = try JSONEncoder().encode(response.content)
            return String(data: data, encoding: .utf8)
        } catch {
            Logger.ai.error("Apple Intelligence advise failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// One-sentence plain-text diagnosis of a failed maintenance module. Logged only, never executed.
    func diagnoseFailure(moduleName: String, error: String) async -> String? {
        guard isAvailable else { return nil }
        let prompt = String("""
            A macOS maintenance module failed. In at most two short sentences, explain the likely cause.
            Do not output shell commands, code or markdown.

            MODULE: \(moduleName)
            ERROR: \(error)
            """.prefix(AutohealAdvisor.maxInputChars))
        return await query(prompt: prompt)
    }

    private func query(prompt: String) async -> String? {
        guard isAvailable else { return nil }
        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            Logger.ai.error("Apple Intelligence query failed: \(error.localizedDescription)")
            return nil
        }
    }
}

enum AIDecision: Sendable, Equatable {
    case kill
    case wait
    case ignore
    case fallbackToRules
}

/// Guided-generation DTO for `adviseHeal`; encoded to the JSON that `AutohealAdvisor.parse` reads.
@Generable(description: "Advice on one self-heal action that the rules already triggered")
struct HealAdvice: Codable {
    @Guide(description: "The action being advised on, exactly as given", .anyOf(HealdCore.HealAction.allCases.map(\.rawValue)))
    var action: String
    @Guide(description: "proceed, defer or skip", .anyOf(AdvisorRecommendation.allCases.map(\.rawValue)))
    var recommendation: String
    @Guide(description: "Confidence between 0 and 1, prefer low if unsure", .range(0.0...1.0))
    var confidence: Double
    @Guide(description: "Very short reason in English, max 280 characters")
    var rationale: String
}
