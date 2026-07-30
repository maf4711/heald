import Foundation
import OSLog
import Security

/// Per-device identity for bank/fleet auth — replaces shared API keys.
/// Stored at `~/.heald/device.json` (mode 0600).
struct DeviceRecord: Codable, Sendable {
    var schema: String = "heald.device/v1"
    var deviceId: String
    var token: String
    var hostname: String
    var enrolledAt: String
    var hardwareUUID: String?
    var serialNumber: String?
}

enum DeviceIdentity {
    static var deviceURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/device.json")
    }

    static func load() -> DeviceRecord? {
        guard let data = try? Data(contentsOf: deviceURL) else { return nil }
        return try? JSONDecoder().decode(DeviceRecord.self, from: data)
    }

    /// Create or return existing enrollment.
    @discardableResult
    static func enroll(force: Bool = false) throws -> DeviceRecord {
        if !force, let existing = load(), !existing.token.isEmpty {
            return existing
        }

        let hw = hardwareUUID()
        let serial = serialNumber()
        let host = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let deviceId = hw ?? UUID().uuidString.lowercased()
        let token = generateToken()

        let rec = DeviceRecord(
            deviceId: deviceId,
            token: token,
            hostname: host,
            enrolledAt: ISO8601DateFormatter().string(from: Date()),
            hardwareUUID: hw,
            serialNumber: serial
        )
        try save(rec)
        Logger.lifecycle.info("Device enrolled id=\(deviceId.prefix(8))…")
        return rec
    }

    static func save(_ rec: DeviceRecord) throws {
        let dir = deviceURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try enc.encode(rec)
        try data.write(to: deviceURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: deviceURL.path
        )
    }

    /// Auth material for cloud: env device token → device.json → HEALD_API_KEY.
    static func bearerToken() -> String? {
        if let e = ProcessInfo.processInfo.environment["HEALD_DEVICE_TOKEN"], !e.isEmpty {
            return e
        }
        if let t = load()?.token, !t.isEmpty { return t }
        if let k = ProcessInfo.processInfo.environment["HEALD_API_KEY"], !k.isEmpty {
            return k
        }
        return nil
    }

    static func machineId() -> String {
        if let e = ProcessInfo.processInfo.environment["HEALD_MACHINE_ID"], !e.isEmpty {
            return e
        }
        if let id = load()?.deviceId, !id.isEmpty { return id }
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = Data(bytes)
        return data.map { String(format: "%02x", $0) }.joined()
    }

    static func hardwareUUID() -> String? {
        let r = ShellRunner.run(
            "/usr/sbin/ioreg",
            arguments: ["-rd1", "-c", "IOPlatformExpertDevice"],
            timeoutSeconds: 5
        )
        let parts = r.output.components(separatedBy: "IOPlatformUUID")
        guard parts.count > 1 else { return nil }
        let tail = parts[1]
        if let m = tail.range(
            of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
            options: .regularExpression
        ) {
            return String(tail[m])
        }
        return nil
    }

    static func serialNumber() -> String? {
        let r = ShellRunner.run(
            "/usr/sbin/system_profiler",
            arguments: ["SPHardwareDataType"],
            timeoutSeconds: 15
        )
        for line in r.output.split(separator: "\n") {
            let s = String(line)
            if s.contains("Serial Number") {
                let parts = s.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    /// MDM enrollment best-effort (profiles status).
    static func mdmEnrollmentStatus() -> [String: Any] {
        let r = ShellRunner.run(
            "/usr/bin/profiles",
            arguments: ["status", "-type", "enrollment"],
            timeoutSeconds: 8
        )
        var out: [String: Any] = [
            "raw": String(r.output.prefix(500)),
            "enrolled": false,
        ]
        let lower = r.output.lowercased()
        if lower.contains("enrolled via") || lower.contains("mdm enrollment: yes")
            || (lower.contains("enrolled") && !lower.contains("not enrolled")) {
            out["enrolled"] = true
        }
        if lower.contains("dep") || lower.contains("ade") {
            out["dep"] = true
        }
        return out
    }
}
