import Foundation
import HealdCore
import Synchronization

/// What the ingest answered inside the outbox `send` closure (Sendable, read after `flush`).
final class PushRecorder: Sendable {
    struct Response: Sendable {
        let status: Int
        let body: Data
    }

    private let state = Mutex<Response?>(nil)
    func record(_ r: Response) { state.withLock { $0 = r } }
    var response: Response? { state.withLock { $0 } }
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
                if redact { f.sample = DiagnosisEngine.cap(PIIRedactor.redact(f.sample), Finding.maxSample) }
                return f
            }
        guard let data = try? DiagnosisEngine.encoder().encode(findings) else { return nil }
        return FindingsSnapshot(data: data, count: findings.count, revision: engine.revision)
    }

    /// POST the body; returns status + response body (throws only on transport errors).
    static func post(_ body: Data, url: String, bearer: String) async throws -> PushRecorder.Response {
        guard let endpoint = URL(string: url) else { throw URLError(.badURL) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let deviceId = DeviceIdentity.load()?.deviceId {
            request.setValue(deviceId, forHTTPHeaderField: "X-Heald-Device-Id")
        }
        request.httpBody = body
        // Shorter than the outbox flush deadline (8 s) so URLSession times out first.
        request.timeoutInterval = IngestPayload.requestTimeout
        let (data, response) = try await URLSession.shared.data(for: request)
        return .init(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: data)
    }
}
