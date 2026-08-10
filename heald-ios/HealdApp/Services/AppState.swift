import Foundation
import SwiftUI

@Observable
final class AppState {
    // Zentrale Key-Konstanten
    private let apiKeyKey = "heald_api_key"
    private let apiURLKey = "heald_api_url"
    private let configuredKey = "heald_is_configured"
    
    var machines: [Machine] = []
    var machineHistory: [String: [MetricSnapshot]] = [:]
    var events: [ActivityEvent] = []
    var isLoading = false
    var error: String?
    var lastRefresh: Date?
    
    private var refreshTimer: Timer?
    private var isRefreshing = false
    
    init() {
        let defaults = UserDefaults.standard
        // Only seed default URL — never a key, and never mark configured without one.
        if defaults.string(forKey: apiURLKey) == nil {
            defaults.set("https://heald.sh", forKey: apiURLKey)
        }
        // Stale flag from older builds that auto-set configured without a key.
        let key = defaults.string(forKey: apiKeyKey) ?? ""
        if key.isEmpty, defaults.bool(forKey: configuredKey) {
            defaults.set(false, forKey: configuredKey)
        }
    }
    
    var healthyCount: Int { machines.filter { $0.status == .healthy }.count }
    var warningCount: Int { machines.filter { $0.status == .warning }.count }
    var criticalCount: Int { machines.filter { $0.status == .critical }.count }
    var offlineCount: Int { machines.filter { $0.status == .offline }.count }

    var aiFixEvents: [ActivityEvent] {
        events.filter { $0.aiGenerated || $0.category == .ai || $0.category == .healing }
    }

    var healthEvents: [ActivityEvent] {
        events.filter { $0.category == .health }
    }

    var isConfigured: Bool {
        let key = UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
        return UserDefaults.standard.bool(forKey: configuredKey) && !key.isEmpty
    }

    func markConfigured() {
        UserDefaults.standard.set(true, forKey: configuredKey)
    }

    func resetConfiguration() {
        UserDefaults.standard.set(false, forKey: configuredKey)
    }

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @MainActor
    func refresh() async {
        guard !isRefreshing else {
            print("[AppState.refresh] Wird bereits ausgeführt – Abbruch.")
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            isLoading = false
        }

        guard isConfigured else {
            print("[AppState.refresh] Nicht konfiguriert – isConfigured = false")
            self.error = "Die App ist nicht konfiguriert. Bitte API-Key und URL einstellen."
            return
        }

        if machines.isEmpty {
            isLoading = true
        }
        error = nil
        
        do {
            async let machinesResult = HealdAPI.shared.fetchMachines()
            async let eventsResult = HealdAPI.shared.fetchEvents()
            
            let (fetchedMachines, fetchedEvents) = try await (machinesResult, eventsResult)
            
            machines = fetchedMachines.map { $0.asMachine }
            for m in fetchedMachines {
                if let history = m.history {
                    machineHistory[m.machineId] = history
                }
            }
            events = fetchedEvents
            lastRefresh = Date()
            print("[AppState.refresh] Daten erfolgreich geladen.")
        } catch let caughtError {
            if let urlError = caughtError as? URLError {
                switch urlError.code {
                case .notConnectedToInternet:
                    self.error = "Keine Internetverbindung."
                case .timedOut:
                    self.error = "Die Anfrage hat zu lange gedauert (Timeout)."
                case .cannotFindHost, .cannotConnectToHost:
                    self.error = "Server nicht erreichbar."
                default:
                    self.error = caughtError.localizedDescription
                }
            } else {
                self.error = caughtError.localizedDescription
            }
            print("[AppState.refresh] Fehler:", caughtError.localizedDescription)
        }
    }
}
