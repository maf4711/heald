import Foundation
import CryptoKit
import ServiceLifecycle
import OSLog

/// Polls heald.sh `/api/update` and auto-replaces `~/Library/heald/heald` when remote is newer.
/// After a successful install, exits so launchd KeepAlive starts the new binary.
///
/// Control:
/// - Env `HEALD_AUTO_UPDATE=0` → off
/// - Policy `autoUpdateEnabled=false` → off
/// - Env `HEALD_UPDATE_INTERVAL_SEC` (default 1800 = 30 min)
struct AutoUpdateService: Service {
    private static let defaultIntervalSec: Int = 1800
    private static let startupDelay: Duration = .seconds(45)

    func run() async throws {
        try await Task.sleep(for: Self.startupDelay)

        while true {
            let policy = await PolicyStore.shared.current()
            if !Self.isAutoUpdateAllowed(policy: policy) {
                Logger.update.info("Auto-update disabled (env/policy)")
                writeStatus(state: "disabled", detail: "HEALD_AUTO_UPDATE=0 or policy.autoUpdateEnabled=false")
                try await Task.sleep(for: .seconds(3600))
                continue
            }

            guard Self.isManagedInstall() else {
                Logger.update.info("Auto-update skipped — not managed install path")
                writeStatus(state: "skipped", detail: "binary not at ~/Library/heald/heald")
                try await Task.sleep(for: .seconds(3600))
                continue
            }

            do {
                if try await Self.checkAndApply(force: false) {
                    Logger.update.info("Auto-update applied — exiting for launchd restart")
                    writeStatus(state: "updated", detail: "restarting")
                    await FleetAck.record(action: "auto_update", result: "ok", detail: "restart")
                    Foundation.exit(0)
                } else {
                    writeStatus(state: "ok", detail: "up to date \(HealdApp.version)")
                }
            } catch {
                Logger.update.warning("Auto-update check failed: \(error.localizedDescription)")
                writeStatus(state: "error", detail: error.localizedDescription)
            }

            try await Task.sleep(for: .seconds(Self.pollIntervalSec()))
        }
    }

    // MARK: - Public (CLI)

    /// Returns true if the binary was replaced (caller should restart).
    @discardableResult
    static func checkAndApply(force: Bool) async throws -> Bool {
        let manifest = try await fetchManifest()
        let local = HealdApp.version

        if !force && !isNewer(manifest.version, than: local) {
            Logger.update.info("Up to date (local \(local), remote \(manifest.version))")
            return false
        }

        if force {
            Logger.update.info("Forced update to \(manifest.version) (local \(local))")
        } else {
            Logger.update.info("Update available: \(local) → \(manifest.version)")
        }

        guard let downloadURL = URL(string: manifest.url) else {
            throw UpdateError.invalidURL(manifest.url)
        }

        let installURL = installBinaryURL()
        let tempURL = installURL.deletingLastPathComponent().appendingPathComponent("heald.download")
        let backupURL = installURL.deletingLastPathComponent().appendingPathComponent("heald.bak")

        try await download(from: downloadURL, to: tempURL)
        try verifyBinary(at: tempURL, expectedSHA256: manifest.sha256)
        try replaceBinary(install: installURL, temp: tempURL, backup: backupURL)

        // Keep /opt/homebrew/bin/heald symlink if it points at us
        refreshHomebrewSymlinkIfNeeded(install: installURL)

        Logger.update.info("Installed heald \(manifest.version) at \(installURL.path)")
        writeStatus(
            state: "installed",
            detail: "\(local) → \(manifest.version)",
            remote: manifest.version
        )
        await FleetAck.record(
            action: "auto_update",
            result: "installed",
            detail: "\(local)->\(manifest.version)"
        )
        return true
    }

    static func fetchManifest() async throws -> UpdateManifest {
        let urlString = updateManifestURL()
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("heald/\(HealdApp.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = DeviceIdentity.bearerToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.manifestHTTP(code)
        }

        let decoded = try JSONDecoder().decode(UpdateManifest.self, from: data)
        guard !decoded.version.isEmpty, !decoded.url.isEmpty else {
            throw UpdateError.invalidManifest
        }
        return decoded
    }

    // MARK: - Config

    static func isAutoUpdateAllowed(policy: PolicyPack) -> Bool {
        if ProcessInfo.processInfo.environment["HEALD_AUTO_UPDATE"] == "0" { return false }
        return policy.autoUpdateEnabled ?? true
    }

    static func pollIntervalSec() -> Int {
        if let s = ProcessInfo.processInfo.environment["HEALD_UPDATE_INTERVAL_SEC"],
           let n = Int(s), n >= 60 {
            return n
        }
        return defaultIntervalSec
    }

    static func installBinaryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/heald/heald")
    }

    static func isManagedInstall() -> Bool {
        let install = installBinaryURL().resolvingSymlinksInPath().path
        guard let exe = resolvedExecutablePath() else { return false }
        return exe == install
    }

    static func resolvedExecutablePath() -> String? {
        if let argv0 = CommandLine.arguments.first {
            let path = URL(fileURLWithPath: argv0).resolvingSymlinksInPath().path
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return Bundle.main.executableURL?.resolvingSymlinksInPath().path
    }

    static func updateManifestURL() -> String {
        if let override = ProcessInfo.processInfo.environment["HEALD_UPDATE_URL"], !override.isEmpty {
            return override
        }
        let ingest = ProcessInfo.processInfo.environment["HEALD_API_URL"]
            ?? "https://heald.sh/api/ingest"
        if let url = URL(string: ingest), let host = url.host {
            let scheme = url.scheme ?? "https"
            let port = url.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)/api/update"
        }
        return "https://heald.sh/api/update"
    }

    static func statusURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data/auto_update.json")
    }

    static func readStatus() -> [String: Any]? {
        guard let data = try? Data(contentsOf: statusURL()),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    // MARK: - Download / verify / replace

    private static func download(from url: URL, to dest: URL) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dest)

        let (tempFile, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.downloadHTTP(code)
        }

        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.moveItem(at: tempFile, to: dest)
    }

    private static func verifyBinary(at url: URL, expectedSHA256: String?) throws {
        let data = try Data(contentsOf: url)
        guard data.count > 1_000_000 else {
            throw UpdateError.binaryTooSmall(data.count)
        }

        let magic = data.prefix(4)
        let isMachO =
            magic == Data([0xCF, 0xFA, 0xED, 0xFE]) ||
            magic == Data([0xCE, 0xFA, 0xED, 0xFE]) ||
            magic == Data([0xCA, 0xFE, 0xBA, 0xBE]) ||
            magic == Data([0xBE, 0xBA, 0xFE, 0xCA]) ||
            magic == Data([0xFE, 0xED, 0xFA, 0xCF]) ||
            magic == Data([0xFE, 0xED, 0xFA, 0xCE])
        guard isMachO else { throw UpdateError.notMachO }

        if let expected = expectedSHA256?.trimmingCharacters(in: .whitespacesAndNewlines),
           !expected.isEmpty {
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex.caseInsensitiveCompare(expected) == .orderedSame else {
                throw UpdateError.sha256Mismatch(expected: expected, actual: hex)
            }
        } else {
            Logger.update.info("No sha256 in manifest — Mach-O size check only")
        }
    }

    private static func replaceBinary(install: URL, temp: URL, backup: URL) throws {
        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)

        if fm.fileExists(atPath: install.path) {
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: install, to: backup)
        }

        do {
            try fm.moveItem(at: temp, to: install)
        } catch {
            if fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: install)
            }
            throw error
        }
        try? fm.removeItem(at: backup)
    }

    private static func refreshHomebrewSymlinkIfNeeded(install: URL) {
        let link = URL(fileURLWithPath: "/opt/homebrew/bin/heald")
        let fm = FileManager.default
        // Only touch if link exists or parent is writable
        guard fm.fileExists(atPath: "/opt/homebrew/bin") else { return }
        try? fm.removeItem(at: link)
        try? fm.createSymbolicLink(at: link, withDestinationURL: install)
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").map { Int($0) ?? 0 }
        let l = local.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(r.count, l.count)
        for i in 0..<n {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private func writeStatus(state: String, detail: String, remote: String? = nil) {
        Self.writeStatus(state: state, detail: detail, remote: remote)
    }

    private static func writeStatus(state: String, detail: String, remote: String? = nil) {
        let dir = statusURL().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var dict: [String: Any] = [
            "schema": "heald.auto_update/v1",
            "ts": ISO8601DateFormatter().string(from: Date()),
            "localVersion": HealdApp.version,
            "state": state,
            "detail": detail,
            "manifestURL": updateManifestURL(),
            "intervalSec": pollIntervalSec(),
        ]
        if let remote { dict["remoteVersion"] = remote }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: statusURL(), options: .atomic)
        }
    }
}

// MARK: - Types

struct UpdateManifest: Decodable, Sendable {
    let version: String
    let url: String
    let sha256: String?
    let minMacOS: String?
    let notes: String?
    let channel: String?

    enum CodingKeys: String, CodingKey {
        case version, url, sha256, minMacOS, notes, channel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        url = try c.decode(String.self, forKey: .url)
        sha256 = try c.decodeIfPresent(String.self, forKey: .sha256)
        minMacOS = try c.decodeIfPresent(String.self, forKey: .minMacOS)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        channel = try c.decodeIfPresent(String.self, forKey: .channel)
    }
}

enum UpdateError: Error, LocalizedError {
    case invalidURL(String)
    case manifestHTTP(Int)
    case invalidManifest
    case downloadHTTP(Int)
    case binaryTooSmall(Int)
    case notMachO
    case sha256Mismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "Invalid update URL: \(u)"
        case .manifestHTTP(let c): return "Update manifest HTTP \(c)"
        case .invalidManifest: return "Update manifest missing version/url"
        case .downloadHTTP(let c): return "Binary download HTTP \(c)"
        case .binaryTooSmall(let n): return "Downloaded binary too small (\(n) bytes)"
        case .notMachO: return "Downloaded file is not a Mach-O binary"
        case .sha256Mismatch(let e, let a): return "SHA-256 mismatch (expected \(e), got \(a))"
        }
    }
}
