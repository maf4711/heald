import Foundation
import HealdCore
import OSLog

/// A scanner-detected fix waiting for `SelfHealOrchestrator.fire` (consent gate + advisor + cooldown).
struct RemediationRequest: Sendable {
    let action: HealdCore.HealAction
    let target: String
    var fingerprints: Set<String>

    /// Queue key: one pending request per (action, target).
    static func key(_ action: HealdCore.HealAction, _ target: String) -> String { "\(action.rawValue):\(target)" }
}

/// Owns the device's `DiagnosisEngine` (persisted to ~/.heald/data/findings.json) and the queue of
/// remediations the scanner requested. The scanner never remediates itself.
actor FindingsStore {
    static let shared = FindingsStore()
    private static let maxPending = 64

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/findings.json")
    }

    private var engine: DiagnosisEngine?
    private var pending: [String: RemediationRequest] = [:]
    /// Engine revision last written; persist only when it moved (dirty tracking).
    private var savedRevision: Int?

    private func loaded() -> DiagnosisEngine {
        if let engine { return engine }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let e = FindingsFile.load(from: url, machineId: DeviceIdentity.machineId())
        engine = e
        return e
    }

    func mutate<T: Sendable>(_ body: @Sendable (inout DiagnosisEngine) -> T) -> T {
        var e = loaded()
        let out = body(&e)
        engine = e
        return out
    }

    func snapshot() -> DiagnosisEngine { loaded() }

    func request(_ action: HealdCore.HealAction, target: String, fingerprint: String) {
        let key = RemediationRequest.key(action, target)
        if pending[key] == nil {
            guard pending.count < Self.maxPending else { return }
            pending[key] = RemediationRequest(action: action, target: target, fingerprints: [])
        }
        pending[key]?.fingerprints.insert(fingerprint)
    }

    /// Targets queued for `action`, without removing them (used for the fire reason).
    func peek(_ action: HealdCore.HealAction) -> [String] {
        pending.values.filter { $0.action == action }.map(\.target).sorted()
    }

    func drain(_ action: HealdCore.HealAction) -> [RemediationRequest] {
        let out = pending.values.filter { $0.action == action }.sorted { $0.target < $1.target }
        for r in out { pending[RemediationRequest.key(r.action, r.target)] = nil }
        return out
    }

    /// Link a heal outcome (from inside a `fire` action) to its findings and persist.
    func recordHeal(_ request: RemediationRequest, succeeded: Bool) {
        let now = Date()
        mutate { e in
            for fp in request.fingerprints {
                e.recordHeal(fingerprint: fp, action: request.action.rawValue, succeeded: succeeded, at: now)
            }
        }
        persist()
    }

    /// Run the lifecycle (open → fixed after the quiet window) and write findings.json atomically.
    func persist() {
        let now = Date()
        mutate { $0.refresh(now: now) }
        let current = loaded()
        guard current.revision != savedRevision else { return }
        do {
            try FindingsFile.save(current, to: Self.fileURL, now: now)
            savedRevision = current.revision
        } catch {
            Logger.health.error("findings.json write failed: \(error.localizedDescription)")
        }
    }
}
