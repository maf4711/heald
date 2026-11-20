import Foundation

/// launchd job failures from `launchctl list` (`PID\tStatus\tLabel`, a few KB — no pipe pressure).
/// Rule ported from daemon-ops-mcp `daemon_health`: last exit status != 0; SIGTERM on unload (-15)
/// is not a failure. Negative status = terminated by that signal (e.g. -9).
extension DiagnosisEngine {
    public static func launchdFailures(from output: String, userName: String? = nil) -> [String: Int] {
        var out: [String: Int] = [:]
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            var cols = raw.split(separator: "\t", omittingEmptySubsequences: false)
            if cols.count != 3 {
                cols = raw.split(maxSplits: 2, whereSeparator: { $0 == " " || $0 == "\t" })
            }
            guard cols.count == 3,
                  let code = Int(cols[1].trimmingCharacters(in: .whitespaces)),
                  code != 0, code != -15 else { continue }
            let label = normalizeLabel(cols[2].trimmingCharacters(in: .whitespaces), userName: userName)
            guard !label.isEmpty else { continue }
            out[label] = code
        }
        return out
    }

    /// `application.<bundle>.<pid>.<pid>` → `application.<bundle>` (per-launch suffix);
    /// the local user name inside a label (`com.<user>.x`) → `~`.
    static func normalizeLabel(_ label: String, userName: String?) -> String {
        var l = label
        if l.hasPrefix("application.") {
            l = RegexCache.replace(#"(\.\d+)+$"#, in: l, with: "")
        }
        if let user = userName, user.count >= 3 {
            l = l.replacingOccurrences(of: user, with: "~", options: .caseInsensitive)
        }
        return l
    }

    /// Ingest jobs whose failure is new or whose exit status changed since `previous`.
    public mutating func ingestLaunchd(
        output: String,
        previous: inout [String: Int],
        at: Date,
        userName: String? = nil
    ) {
        let current = Self.launchdFailures(from: output, userName: userName)
        for (label, code) in current.sorted(by: { $0.key < $1.key }) where previous[label] != code {
            ingest(Observation(
                category: .launchdJob,
                component: label,
                signature: "",
                source: .launchd,
                at: at,
                sample: "launchd job \(label) last exit status \(code)",
                severityOverride: Self.launchdSeverity(label: label, code: code)
            ))
        }
        previous = current
    }

    /// SIGKILL (-9) of an Apple agent is almost always jetsam / memory pressure → warning;
    /// every other failure (incl. -9 of third-party jobs) stays error.
    public static func launchdSeverity(label: String, code: Int) -> FindingSeverity {
        code == -9 && label.hasPrefix("com.apple.") ? .warning : .error
    }

    /// Seed for `previous` after a daemon restart: label → exit status of open launchd findings,
    /// so an unchanged failure is not counted again.
    public func launchdBaseline() -> [String: Int] {
        var out: [String: Int] = [:]
        for f in findings where f.category == .launchdJob && f.status != .fixed {
            guard let label = RegexCache.firstMatch(#"^launchd job (\S+) last exit status -?\d+$"#, in: f.sample),
                  let code = RegexCache.firstMatch(#"last exit status (-?\d+)$"#, in: f.sample).flatMap({ Int($0) })
            else { continue }
            out[label] = code
        }
        return out
    }
}
