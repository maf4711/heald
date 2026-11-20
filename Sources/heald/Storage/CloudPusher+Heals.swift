import Foundation
import HealdCore
import Synchronization

/// Set once by the outbox `send` closure when the POST returned 200.
final class PushFlag: Sendable {
    private let state = Mutex(false)
    func set() { state.withLock { $0 = true } }
    var isSet: Bool { state.withLock { $0 } }
}

/// Findings are sent when the engine revision moved, and re-sent every `resendEvery` pushes
/// so a dashboard cold start re-learns the current picture.
struct FindingsPushGate {
    static let resendEvery = 30 // × 10 s push interval = 5 min
    private var lastRevision: Int?
    private var pushesSince = 0

    func due(revision: Int) -> Bool {
        lastRevision != revision || pushesSince >= Self.resendEvery
    }

    mutating func sent(revision: Int?) {
        if let revision {
            lastRevision = revision
            pushesSince = 0
        } else {
            pushesSince += 1
        }
    }
}

struct FindingsSnapshot: Sendable {
    let data: Data
    let count: Int
    let revision: Int
}

extension CloudPusher {
    /// Dashboard caps one array at 500 per request; findings.json holds ≤ 500 already.
    static let maxFindingsPerPush = 500

    /// Current findings (newest first), encoded with the GOAL 3 findings encoder; nil when not due.
    func findingsJSON(redact: Bool, gate: FindingsPushGate) async -> FindingsSnapshot? {
        let engine = await FindingsStore.shared.snapshot()
        guard gate.due(revision: engine.revision) else { return nil }
        let id = DeviceIdentity.machineId()
        let findings = engine.findings
            .sorted { $0.lastSeen > $1.lastSeen }
            .prefix(Self.maxFindingsPerPush)
            .map { f -> Finding in
                var f = f
                f.machineId = id
                if redact { f.sample = Self.capUTF16(PIIRedactor.redact(f.sample), Finding.maxSample) }
                return f
            }
        guard let data = try? DiagnosisEngine.encoder().encode(findings) else { return nil }
        return FindingsSnapshot(data: data, count: findings.count, revision: engine.revision)
    }

    /// Ingest body: the metrics/events payload plus `heals` (always) and `findings` (when due).
    static func body(base: Data, heals: [HealReport], findings: Data?) throws -> Data {
        guard var dict = try JSONSerialization.jsonObject(with: base) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        dict["heals"] = try JSONSerialization.jsonObject(with: DiagnosisEngine.encoder().encode(heals))
        if let findings { dict["findings"] = try JSONSerialization.jsonObject(with: findings) }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func capUTF16(_ s: String, _ n: Int) -> String {
        var out = s
        while out.utf16.count > n { out.removeLast() }
        return out
    }
}
