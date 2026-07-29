import Foundation
import CryptoKit
import ServiceLifecycle
import OSLog

/// Periodically checks heald.sh `/api/update` and replaces the installed binary when newer.
/// After a successful replace, exits so launchd KeepAlive restarts the new binary.
struct AutoUpdateService: Service {
    /// How often to poll the update manifest.
    private static let checkInterval: Duration = .seconds(6 * 3600)
    /// Short delay after start so collectors come up first.
    private static let startupDelay: Duration = .seconds(30)

    func run() async throws {
        if ProcessInfo.processInfo.environment["HEALD_AUTO_UPDATE"] == "0" {
            Logger.update.info("Auto-update disabled (HEALD_AUTO_UPDATE=0)")
            while true { try await Task.sleep(for: .seconds(3600)) }
        }

        guard Self.isManagedInstall() else {
            Logger.update.info("Auto-update skipped — binary not at ~/Library/heald/heald")
            while true { try await Task.sleep(for: .seconds(3600)) }
        }

        try await Task.sleep(for: Self.startupDelay)

        while true {
            do {
                if try await Self.checkAndApply(force: false) {
                    Logger.update.info("Auto-update applied — exiting for launchd restart")
                    // launchd KeepAlive will relaunch the new binary
                    Foundation.exit(0)
                }
            } catch {
                Logger.update.warning("Auto-update check failed: \(error.localizedDescription)")
            }
            try await Task.sleep(for: Self.checkInterval)
        }
    }

    // MARK: - Public (CLI)

    /// Returns true if the binary was replaced and the process should exit/restart.
    @discardableResult
    static func checkAndApply(force: Bool) async throws -> Bool {
        let manifest = try await fetchManifest()
        let local = HealdApp.version

        if !force && !isNewer(manifest.version, than: local) {
            Logger.update.info("Up to date (local \(local), remote \(manifest.version))")
            return false
        }

        if !force {
            Logger.update.info("Update available: \(local) → \(manifest.version)")
        } else {
            Logger.update.info("Forced update to \(manifest.version) (local \(local))")
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

        Logger.update.info("Installed heald \(manifest.version) at \(installURL.path)")
        return true
    }

    static func fetchManifest() async throws -> UpdateManifest {
        let urlString = updateManifestURL()
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("heald/\(HealdApp.version)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

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

    // MARK: - Paths / config

    static func installBinaryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/heald/heald")
    }

    /// Only self-update when we are the managed install path (not brew cellar / build dir).
    static func isManagedInstall() -> Bool {
        let install = installBinaryURL().resolvingSymlinksInPath().path
        guard let exe = resolvedExecutablePath() else { return false }
        return exe == install
    }

    static func resolvedExecutablePath() -> String? {
        // Prefer argv0 (launchd / CLI); resolve symlinks (e.g. /opt/homebrew/bin/heald → Library/heald).
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

    // MARK: - Download / verify / replace

    private static func download(from url: URL, to dest: URL) async throws {
        let fm = FileManager.default
        try? fm.removeItem(at: dest)

        let (tempFile, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.downloadHTTP(code)
        }

        // Ensure parent exists
        try fm.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fm.fileExists(atPath: dest.path) {
            try fm.removeItem(at: dest)
        }
        try fm.moveItem(at: tempFile, to: dest)
    }

    private static func verifyBinary(at url: URL, expectedSHA256: String?) throws {
        let data = try Data(contentsOf: url)
        guard data.count > 1_000_000 else {
            throw UpdateError.binaryTooSmall(data.count)
        }

        // Mach-O magic (MH_MAGIC_64 / fat)
        let magic = data.prefix(4)
        let isMachO =
            magic == Data([0xCF, 0xFA, 0xED, 0xFE]) || // MH_MAGIC_64 LE
            magic == Data([0xCE, 0xFA, 0xED, 0xFE]) || // MH_MAGIC LE
            magic == Data([0xCA, 0xFE, 0xBA, 0xBE]) || // FAT
            magic == Data([0xBE, 0xBA, 0xFE, 0xCA]) || // FAT swapped
            magic == Data([0xFE, 0xED, 0xFA, 0xCF]) || // MH_MAGIC_64 BE
            magic == Data([0xFE, 0xED, 0xFA, 0xCE])    // MH_MAGIC BE
        guard isMachO else {
            throw UpdateError.notMachO
        }

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

        // Executable bits
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temp.path)

        // Atomic-ish swap: backup current → move new into place
        if fm.fileExists(atPath: install.path) {
            try? fm.removeItem(at: backup)
            try fm.moveItem(at: install, to: backup)
        }

        do {
            try fm.moveItem(at: temp, to: install)
        } catch {
            // Roll back
            if fm.fileExists(atPath: backup.path) {
                try? fm.moveItem(at: backup, to: install)
            }
            throw error
        }

        try? fm.removeItem(at: backup)
    }

    /// Semantic-ish version compare (numeric components only).
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
}

// MARK: - Types

struct UpdateManifest: Decodable, Sendable {
    let version: String
    let url: String
    let sha256: String?
    let minMacOS: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case version, url, sha256, minMacOS, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(String.self, forKey: .version)
        url = try c.decode(String.self, forKey: .url)
        // API may send null
        if let s = try c.decodeIfPresent(String.self, forKey: .sha256) {
            sha256 = s
        } else {
            sha256 = nil
        }
        minMacOS = try c.decodeIfPresent(String.self, forKey: .minMacOS)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
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
