import Foundation
import HealdCore
import OSLog

/// Light scanner for device errors, feeding `DiagnosisEngine` (findings.json):
/// 1) New DiagnosticReports (`.ips` / `.crash` / `.diag` / `.panic`) under user + system logs
/// 2) Recent unified-log **fault** lines for critical processes
/// 3) launchd jobs in the gui domain with a non-zero last exit status
///
/// Logs every hit to `ActivityLog` (crash_detected / system_fault, unchanged) and only **requests**
/// fixes (`app_restart`, `dns_flush`) — `SelfHealOrchestrator.fire` runs them behind the consent gate.
actor SystemErrorScanner {
    private var reports = ReportSeenState()
    private var stateLoaded = false
    private let stateURL: URL
    private var lastFaultLines: Set<String> = []
    /// nil until seeded from open launchd findings (so a daemon restart does not re-count them).
    private var lastLaunchdFailures: [String: Int]?

    private static let reportExtensions: Set<String> = ["ips", "crash", "diag", "panic"]
    private static let maxReportBytes = 256 * 1024

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
        await scanLaunchdJobs()
        await FindingsStore.shared.persist()
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
        var found: [(path: String, mtime: Date)] = []

        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in items {
                guard Self.reportExtensions.contains(url.pathExtension.lowercased()),
                      let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                      vals.isRegularFile == true,
                      let mtime = vals.contentModificationDate,
                      mtime >= cutoff else { continue }
                found.append((url.path, mtime))
            }
        }

        // First run: mark existing reports seen (avoid flood on daemon start)
        let wasPrimed = reports.primed
        let mtimes = Dictionary(found.map { ($0.path, $0.mtime) }, uniquingKeysWith: max)
        let fresh = reports.fresh(found.sorted { $0.mtime < $1.mtime }.map(\.path), limit: 20)
        reports.retain(current: Set(found.map(\.path))) // age-based trim: drop paths past the 24 h cutoff
        if !wasPrimed {
            Logger.health.info("SystemErrorScanner primed with \(self.reports.seen.count) existing reports")
            return
        }

        for path in fresh {
            let filename = (path as NSString).lastPathComponent
            let app = DiagnosisEngine.processName(fromReportFilename: filename)
            Logger.health.warning("Crash report: \(app) — \(path)")

            try? await activityLog.log(event: ActivityEvent(
                type: .crashDetected,
                summary: "Crash report: \(app)",
                detail: path,
                beforeState: "process crashed",
                afterState: nil
            ))

            let contents = PIIRedactor.redact(readReport(path))
            let at = mtimes[path] ?? Date()
            guard let hit = await FindingsStore.shared.mutate({
                $0.ingestReport(filename: filename, contents: contents, at: at)
            }) else { continue }

            // Every crash of a restartable app → request; the executor inside fire checks isRunning.
            if DiagnosisEngine.remediation(for: hit.observation) == .appRestart {
                await FindingsStore.shared.request(.appRestart, target: app, fingerprint: hit.fingerprint)
            }
        }
    }

    private func readReport(_ path: String) -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? h.close() }
        let data = (try? h.read(upToCount: Self.maxReportBytes)) ?? Data()
        return String(decoding: data, as: UTF8.self)
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

        // The 90 s window overlaps the 60 s cadence: count each line once.
        let fresh = DiagnosisEngine.freshLines(lines, seen: &lastFaultLines).map(PIIRedactor.redact)
        guard !fresh.isEmpty else { return }

        let now = Date()
        let byProcess = await FindingsStore.shared.mutate { $0.ingestFaultLines(fresh, at: now) }

        for (proc, count) in byProcess.sorted(by: { $0.key < $1.key }) {
            let sample = fresh.first(where: { $0.contains(proc) }) ?? fresh[0]
            try? await activityLog.log(event: ActivityEvent(
                type: .systemFault,
                summary: "System fault: \(proc) ×\(count) (last 90s)",
                detail: String(sample.prefix(400))
            ))
            Logger.health.warning("Unified log fault: \(proc) ×\(count)")

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

        if DiagnosisEngine.dnsFlushNeeded(faultCounts: byProcess) {
            // Linked to the mDNSResponder fault finding only — never to a crash finding.
            await FindingsStore.shared.request(
                .dnsFlush, target: "mDNSResponder", fingerprint: DiagnosisEngine.dnsFlushFingerprint
            )
        }
    }

    // MARK: - launchd jobs

    private func scanLaunchdJobs() async {
        // `launchctl list` (gui domain of this user, PID/Status/Label) — small, stable output.
        let result = ShellRunner.run("/bin/launchctl", arguments: ["list"], timeoutSeconds: 5)
        guard result.succeeded else { return }
        let seeded = lastLaunchdFailures
        let now = Date()
        let output = result.output
        let user = NSUserName()
        lastLaunchdFailures = await FindingsStore.shared.mutate { e in
            var previous = seeded ?? e.launchdBaseline()
            e.ingestLaunchd(output: output, previous: &previous, at: now, userName: user)
            return previous
        }
    }

    // MARK: - Helpers

    private func ensureStateLoaded() {
        guard !stateLoaded else { return }
        stateLoaded = true
        guard let data = try? Data(contentsOf: stateURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let seen = Set(obj["seen"] as? [String] ?? [])
        reports = ReportSeenState(seen: seen, primed: obj["primed"] as? Bool ?? !seen.isEmpty)
    }

    private func saveState() {
        let dict: [String: Any] = [
            "primed": reports.primed,
            "seen": Array(reports.seen.prefix(1000)),
            "ts": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
