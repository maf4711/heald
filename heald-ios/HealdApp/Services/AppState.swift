import Foundation
import SwiftUI

@Observable
final class AppState {
    var machines: [Machine] = []
    var machineHistory: [String: [MetricSnapshot]] = [:]
    var events: [ActivityEvent] = []
    var isLoading = false
    var error: String?
    var lastRefresh: Date?

    private var refreshTimer: Timer?

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
        let key = UserDefaults.standard.string(forKey: "heald_api_key") ?? ""
        return !key.isEmpty
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
        guard isConfigured else { return }

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
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
