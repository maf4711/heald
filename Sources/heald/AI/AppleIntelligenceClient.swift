import Foundation
import OSLog
import FoundationModels

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

    /// Suggest a non-interactive shell fix for a failed maintenance module.
    func selfHealAnalyze(moduleName: String, error: String) async -> String? {
        guard isAvailable else { return nil }

        let prompt = """
            Du bist ein macOS System-Administrator. Ein Wartungsmodul ist fehlgeschlagen.

            MODUL: \(moduleName)
            FEHLER: \(error)

            SYSTEM: macOS Apple Silicon, Homebrew, Swift daemon (LaunchAgent), Apple Intelligence on-device

            Liefere NUR den Fix-Befehl (Shell-Commands, eine pro Zeile).
            Keine Erklaerungen. Kein Markdown. Muss ohne Interaktion laufen.
            Wenn kein Fix moeglich: nur NOFIX
            """

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
