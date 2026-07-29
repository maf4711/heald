import Foundation
import OSLog

/// Light scanner for system faults:
/// 1) New DiagnosticReports (`.ips` / `.crash`) under user + system logs
/// 2) Recent unified-log **fault** lines for critical processes
///
/// Logs every finding to `ActivityLog` and applies **safe** remediations only
/// (restart known UI processes, DNS flush on mDNSResponder faults).
actor SystemErrorScanner {
    private var seenReports: Set<String> = []
    private var primed = false
    private var stateLoaded = false
    private let stateURL: URL

    /// Processes we may restart after a crash report.
    private static let restartable: Set<String> = [
        "Finder", "Dock", "SystemUIServer", "NotificationCenter",
        "ControlCenter", "WallpaperAgent", "WindowManager",
    ]

    /// Unified-log process names worth watching (fault).
    private static let logWatchProcesses = [
        "bird", "cloudd", "fileproviderd", "mds", "mds_stores",
        "mDNSResponder", "WindowServer", "kernel_task",
    ]

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/data")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stateURL = dir.appendingPathComponent("error_scanner_seen.json")
    }

    /// Run one scan cycle (call ~every 60s).
    func scan(activityLog: ActivityLog) async {
        ensureStateLoaded()
        await scanDiagnosticReports(activityLog: activityLog)
        await scanUnifiedLogFaults(activityLog: activityLog)
        saveState()
    }

    // MARK: - DiagnosticReports

    private func scanDiagnosticReports(activityLog: ActivityLog) async {
        let dirs = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/DiagnosticReports"),
            URL(fileURLWithPath: "/Library/Logs/DiagnosticReports"),
        ]

        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        var found: [(path: String, name: String, mtime: Date)] = []

        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in items {
                let ext = url.pathExtension.lowercased()
                guard ext == "ips" || ext == "crash" || ext == "diag" else { continue }
                guard let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      vals.isRegularFile == true,
                      let mtime = vals.contentModificationDate,
                      mtime >= cutoff else { continue }
                found.append((url.path, processName(fromReportFilename: url.lastPathComponent), mtime))
            }
        }

        // First run: mark existing reports seen (avoid flood on daemon start)
        if !primed {
            for f in found { seenReports.insert(f.path) }
            primed = true
            Logger.health.info("SystemErrorScanner primed with \(self.seenReports.count) existing reports")
            return
        }

        let fresh = found.filter { !seenReports.contains($0.path) }
            .sorted { $0.mtime < $1.mtime }

        for item in fresh.prefix(20) {
            seenReports.insert(item.path)
            let app = item.name
            Logger.health.warning("Crash report: \(app) — \(item.path)")

            try? await activityLog.log(event: ActivityEvent(
                type: .crashDetected,
                summary: "Crash report: \(app)",
                detail: item.path,
                beforeState: "process crashed",
                afterState: nil
            ))

            if Self.restartable.contains(app) {
                if !isRunning(app) {
                    let ok = restartApp(app)
                    try? await activityLog.log(event: ActivityEvent(
                        type: ok ? .processRestarted : .healingFailed,
                        summary: ok ? "Restarted \(app) after crash" : "Failed to restart \(app)",
                        detail: item.path,
                        beforeState: "\(app) not running",
                        afterState: ok ? "restarted" : "still down"
                    ))
                    if ok {
                        Logger.health.info("Self-heal: restarted \(app)")
                    }
                } else {
                    try? await activityLog.log(event: ActivityEvent(
                        type: .selfHealed,
                        summary: "Crash noted for \(app) (already running again)",
                        detail: item.path
                    ))
                }
            }
        }

        if seenReports.count > 2000 {
            seenReports = Set(seenReports.suffix(1000))
        }
    }

    // MARK: - Unified log faults

    private func scanUnifiedLogFaults(activityLog: ActivityLog) async {
        let processClause = Self.logWatchProcesses
            .map { "process == \"\($0)\"" }
            .joined(separator: " OR ")
        let predicate = "(messageType == fault) AND (\(processClause))"

        let result = ShellRunner.run(
            "/usr/bin/log",
            arguments: [
                "show",
                "--style", "compact",
                "--last", "90s",
                "--predicate", predicate,
            ],
            timeoutSeconds: 12
        )

        guard result.succeeded || !result.output.isEmpty else { return }

        let lines = result.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard !lines.isEmpty else { return }

        var byProcess: [String: Int] = [:]
        for line in lines {
            let proc = extractProcess(fromLogLine: line) ?? "unknown"
            byProcess[proc, default: 0] += 1
        }

        for (proc, count) in byProcess.sorted(by: { $0.key < $1.key }) {
            let sample = lines.first(where: { $0.contains(proc) }) ?? lines[0]
            try? await activityLog.log(event: ActivityEvent(
                type: .systemFault,
                summary: "System fault: \(proc) ×\(count) (last 90s)",
                detail: String(sample.prefix(400))
            ))
            Logger.health.warning("Unified log fault: \(proc) ×\(count)")

            if proc == "mDNSResponder", count >= 3 {
                flushDNS()
                try? await activityLog.log(event: ActivityEvent(
                    type: .dnsFlushed,
                    summary: "DNS flushed after mDNSResponder faults",
                    detail: "fault count=\(count)"
                ))
            }

            if (proc == "mds" || proc == "mds_stores"), count >= 5 {
                try? await activityLog.log(event: ActivityEvent(
                    type: .spotlightStuck,
                    summary: "Spotlight process faults elevated (\(proc) ×\(count))",
                    detail: "Consider: heald maintain --profile quick"
                ))
            }

            if (proc == "bird" || proc == "cloudd" || proc == "fileproviderd"), count >= 3 {
                try? await activityLog.log(event: ActivityEvent(
                    type: .icloudSyncDegraded,
                    summary: "iCloud daemon faults: \(proc) ×\(count)",
                    detail: String(sample.prefix(300))
                ))
            }
        }
    }

    // MARK: - Helpers

    private func processName(fromReportFilename name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        if let range = base.range(of: #"-\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) {
            return String(base[..<range.lowerBound])
        }
        if let range = base.range(of: #"-\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            return String(base[..<range.lowerBound])
        }
        return base
    }

    private func extractProcess(fromLogLine line: String) -> String? {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count >= 4 else { return nil }
        var token = String(parts[3])
        if let bracket = token.firstIndex(of: "[") {
            token = String(token[..<bracket])
        }
        if token.hasSuffix(":") { token = String(token.dropLast()) }
        return token.isEmpty ? nil : token
    }

    private func isRunning(_ name: String) -> Bool {
        ShellRunner.run("/usr/bin/pgrep", arguments: ["-x", name], timeoutSeconds: 3).succeeded
    }

    private func restartApp(_ name: String) -> Bool {
        ShellRunner.run("/usr/bin/open", arguments: ["-a", name], timeoutSeconds: 10).succeeded
    }

    private func flushDNS() {
        _ = ShellRunner.run("/usr/bin/dscacheutil", arguments: ["-flushcache"], timeoutSeconds: 5)
        _ = ShellRunner.run("/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"], timeoutSeconds: 3)
    }

    private func ensureStateLoaded() {
        guard !stateLoaded else { return }
        stateLoaded = true
        guard let data = try? Data(contentsOf: stateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let arr = obj["seen"] as? [String] {
            seenReports = Set(arr)
        }
        primed = obj["primed"] as? Bool ?? !seenReports.isEmpty
    }

    private func saveState() {
        let dict: [String: Any] = [
            "primed": primed,
            "seen": Array(seenReports.suffix(1000)),
            "ts": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
