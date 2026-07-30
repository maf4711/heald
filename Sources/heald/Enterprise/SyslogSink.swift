import Foundation
import ServiceLifecycle
import OSLog
import Network

/// Lightweight UDP syslog (RFC 5424-ish) for SIEM pilots.
/// Enable: policy.siemSyslogEnabled or HEALD_SIEM_HOST.
struct SyslogSink: Service {
    let activityLog: ActivityLog

    private static let interval: Duration = .seconds(15)
    private static let batch = 30

    func run() async throws {
        var cursor = loadCursor()
        if !cursorFileExists() {
            if let eof = try? await activityLog.endOffset() {
                cursor = eof
                saveCursor(cursor)
            }
        }

        while true {
            try await Task.sleep(for: Self.interval)
            let policy = await PolicyStore.shared.current()
            let host = ProcessInfo.processInfo.environment["HEALD_SIEM_HOST"]
                ?? policy.siemSyslogHost
            let enabled = policy.siemSyslogEnabled
                || !(ProcessInfo.processInfo.environment["HEALD_SIEM_HOST"] ?? "").isEmpty
            guard enabled, let host, !host.isEmpty else { continue }

            let port = UInt16(
                ProcessInfo.processInfo.environment["HEALD_SIEM_PORT"].flatMap(UInt16.init)
                    ?? policy.siemSyslogPort
            )

            do {
                let batch = try await activityLog.readEvents(since: cursor, limit: Self.batch)
                guard !batch.events.isEmpty else { continue }
                let redact = policy.piiRedaction
                for e in batch.events {
                    var summary = e.summary
                    var detail = e.detail ?? ""
                    if redact {
                        summary = PIIRedactor.redact(summary)
                        detail = PIIRedactor.redact(detail)
                    }
                    let msg = "heald[\(HealdApp.version)] \(e.type.rawValue): \(summary) \(detail)"
                    try await sendUDP(host: host, port: port, message: formatSyslog(msg))
                }
                cursor = batch.nextOffset
                saveCursor(cursor)
                Logger.storage.debug("SyslogSink: sent \(batch.events.count) events → \(host):\(port)")
            } catch {
                Logger.storage.warning("SyslogSink: \(error.localizedDescription)")
            }
        }
    }

    private func formatSyslog(_ msg: String) -> String {
        // <134> = local0.info
        let host = Host.current().localizedName ?? "mac"
        let ts = ISO8601DateFormatter().string(from: Date())
        return "<134>1 \(ts) \(host) heald - - - \(msg)\n"
    }

    private func sendUDP(host: String, port: UInt16, message: String) async throws {
        guard let data = message.data(using: .utf8) else { return }
        // Use a simple connected UDP socket via NWConnection
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? 514,
                using: .udp
            )
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: data, completion: .contentProcessed { error in
                        connection.cancel()
                        if let error {
                            cont.resume(throwing: error)
                        } else {
                            cont.resume()
                        }
                    })
                case .failed(let error):
                    connection.cancel()
                    cont.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private var cursorURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/siem_cursor")
    }

    private func cursorFileExists() -> Bool {
        FileManager.default.fileExists(atPath: cursorURL.path)
    }

    private func loadCursor() -> UInt64 {
        guard let raw = try? String(contentsOf: cursorURL, encoding: .utf8),
              let v = UInt64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return v
    }

    private func saveCursor(_ offset: UInt64) {
        let dir = cursorURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? String(offset).write(to: cursorURL, atomically: true, encoding: .utf8)
    }
}
