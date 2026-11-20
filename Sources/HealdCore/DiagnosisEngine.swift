import Foundation

/// Pure device diagnosis: classify log inputs, fingerprint, dedupe, and run the finding lifecycle
/// (open → fixed after a successful linked heal + quiet window → recurring on a new occurrence).
/// I/O (reading reports, `log show`, `launchctl`, findings.json) lives in the heald target.
public struct DiagnosisEngine: Sendable {
    public static let maxFindings = 500
    /// A healed finding is `fixed` once no new occurrence arrived for this long after the heal.
    public static let quietWindow: TimeInterval = 30 * 60

    /// UI processes the daemon may relaunch after a crash (`app_restart`).
    public static let restartableApps: Set<String> = [
        "Finder", "Dock", "SystemUIServer", "NotificationCenter",
        "ControlCenter", "WallpaperAgent", "WindowManager",
    ]
    /// mDNSResponder faults per scan that trigger `dns_flush`.
    public static let dnsFaultThreshold = 3

    public var machineId: String {
        didSet { for k in byFingerprint.keys { byFingerprint[k]?.machineId = machineId } }
    }
    /// Inputs that could not be classified (empty / binary / malformed). Never fatal.
    public private(set) var unparsed: Int
    private var byFingerprint: [String: Finding]

    public init(machineId: String, findings: [Finding] = [], unparsed: Int = 0) {
        self.machineId = machineId
        self.unparsed = unparsed
        var map: [String: Finding] = [:]
        for var f in findings {
            f.machineId = machineId
            map[f.fingerprint] = f
        }
        byFingerprint = map
    }

    /// All findings, ordered by fingerprint (stable for diffing / persistence).
    public var findings: [Finding] {
        byFingerprint.values.sorted { $0.fingerprint < $1.fingerprint }
    }

    /// Findings that still need attention (open or recurring), most severe first.
    public var activeFindings: [Finding] {
        byFingerprint.values
            .filter { $0.status != .fixed }
            .sorted { ($0.severity, $0.lastSeen) > ($1.severity, $1.lastSeen) }
    }

    public func finding(_ fingerprint: String) -> Finding? { byFingerprint[fingerprint] }

    public mutating func noteUnparsed(_ n: Int = 1) { unparsed += n }

    // MARK: - Severity + fingerprint

    /// Fixed severity table: panic=critical, crash of restartable app=warning, other crash=error,
    /// fault=warning, launchd job failure=error.
    public static func severity(category: FindingCategory, component: String) -> FindingSeverity {
        switch category {
        case .panic: .critical
        case .crash: restartableApps.contains(component) ? .warning : .error
        case .fault: .warning
        case .launchdJob: .error
        }
    }

    public static func fingerprint(category: FindingCategory, component: String, signature: String) -> String {
        let prefix = category == .launchdJob ? "launchd" : category.rawValue
        let parts = [prefix, cap(redactPaths(component), Finding.maxShort)]
            + (signature.isEmpty ? [] : [redactPaths(signature)])
        return cap(parts.joined(separator: ":"), Finding.maxFingerprint)
    }

    public static func fingerprint(for o: Observation) -> String {
        fingerprint(category: o.category, component: o.component, signature: o.signature)
    }

    /// `/Users/<name>/…` → `/Users/~/…` so fingerprints and samples carry no user names.
    public static func redactPaths(_ s: String) -> String {
        s.replacingOccurrences(of: #"/Users/[^/\s"]+"#, with: "/Users/~", options: .regularExpression)
    }

    static func cap(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n))
    }

    /// Fingerprint an observation will merge into: a unified-log fault joins the most recent
    /// crash finding of the same component, so one component failure is one finding.
    public func resolveFingerprint(for o: Observation) -> String {
        if o.category == .fault, o.source == .unifiedLog {
            let component = Self.cap(Self.redactPaths(o.component), Finding.maxShort)
            if let crash = byFingerprint.values
                .filter({ $0.category == .crash && $0.component == component })
                .max(by: { $0.lastSeen < $1.lastSeen }) {
                return crash.fingerprint
            }
        }
        return Self.fingerprint(for: o)
    }

    // MARK: - Ingest + lifecycle

    @discardableResult
    public mutating func ingest(_ o: Observation) -> String {
        let fp = resolveFingerprint(for: o)
        let sample = Self.cap(Self.redactPaths(o.sample), Finding.maxSample)
        let source = Self.cap(o.source.rawValue, Finding.maxSourceChars)
        let severity = Self.severity(category: o.category, component: o.component)

        guard var f = byFingerprint[fp] else {
            byFingerprint[fp] = Finding(
                machineId: machineId,
                fingerprint: fp,
                category: o.category,
                component: Self.cap(Self.redactPaths(o.component), Finding.maxShort),
                severity: severity,
                count: 1,
                firstSeen: o.at,
                lastSeen: o.at,
                status: .open,
                recurrenceCount: 0,
                sources: [source],
                linkedAction: nil,
                sample: sample
            )
            evict()
            return fp
        }
        f.count += 1
        f.firstSeen = min(f.firstSeen, o.at)
        f.lastSeen = max(f.lastSeen, o.at)
        f.severity = max(f.severity, severity)
        f.sample = sample
        if !f.sources.contains(source), f.sources.count < Finding.maxSources {
            f.sources.append(source)
        }
        if f.status == .fixed {
            f.status = .recurring
            f.recurrenceCount += 1
            f.healedAt = nil
        }
        byFingerprint[fp] = f
        return fp
    }

    /// Link a heal outcome to a finding. Only a successful heal (`executed_ok`) can lead to `fixed`.
    public mutating func recordHeal(fingerprint: String, action: String, succeeded: Bool, at: Date) {
        guard var f = byFingerprint[fingerprint] else { return }
        f.linkedAction = Self.cap(action, Finding.maxShort)
        f.healedAt = succeeded ? at : nil
        byFingerprint[fingerprint] = f
    }

    /// open/recurring → fixed when the linked heal succeeded and nothing new arrived for `quietWindow`.
    public mutating func refresh(now: Date) {
        for (fp, f) in byFingerprint where f.status != .fixed {
            guard let healed = f.healedAt, f.lastSeen <= healed,
                  now.timeIntervalSince(healed) >= Self.quietWindow else { continue }
            byFingerprint[fp]?.status = .fixed
        }
        evict()
    }

    /// Keep at most `maxFindings`: evict the oldest fixed findings first; open/recurring never.
    private mutating func evict() {
        let excess = byFingerprint.count - Self.maxFindings
        guard excess > 0 else { return }
        let victims = byFingerprint.values
            .filter { $0.status == .fixed }
            .sorted { $0.lastSeen < $1.lastSeen }
            .prefix(excess)
        for v in victims { byFingerprint[v.fingerprint] = nil }
    }

    // MARK: - Source adapters (classify + ingest, count unparsed)

    /// Classify one diagnostic report; unparseable input is counted, never thrown.
    @discardableResult
    public mutating func ingestReport(
        filename: String,
        contents: String,
        at: Date
    ) -> (observation: Observation, fingerprint: String)? {
        guard let o = Self.classifyReport(filename: filename, contents: contents, at: at) else {
            unparsed += 1
            return nil
        }
        return (o, ingest(o))
    }

    /// Ingest unified-log fault lines (one occurrence per line); returns fault count per process.
    @discardableResult
    public mutating func ingestFaultLines(_ lines: [String], at: Date) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("Filtering the log data") || trimmed.hasPrefix("Timestamp") {
                continue
            }
            guard let o = Self.classifyFaultLine(trimmed, at: at) else {
                unparsed += 1
                continue
            }
            ingest(o)
            counts[o.component, default: 0] += 1
        }
        return counts
    }

    /// Ingest launchd job failures that are new or changed exit status since `previous`.
    public mutating func ingestLaunchd(output: String, previous: inout [String: Int], at: Date) {
        let current = Self.launchdFailures(from: output)
        for (label, code) in current.sorted(by: { $0.key < $1.key }) where previous[label] != code {
            ingest(Observation(
                category: .launchdJob,
                component: label,
                signature: "",
                source: .launchd,
                at: at,
                sample: "launchd job \(label) last exit status \(code)"
            ))
        }
        previous = current
    }

    /// Lines not seen in the previous scan (the 90 s `log show` window overlaps the 60 s cadence).
    public static func freshLines(_ lines: [String], seen: inout Set<String>) -> [String] {
        let fresh = lines.filter { !seen.contains($0) }
        seen = Set(lines)
        return fresh
    }

    // MARK: - Remediation planning (execution only via SelfHealOrchestrator.fire consent gate)

    public static func remediation(for o: Observation, isRunning: Bool) -> HealAction? {
        o.category == .crash && restartableApps.contains(o.component) && !isRunning ? .appRestart : nil
    }

    public static func dnsFlushNeeded(faultCounts: [String: Int]) -> Bool {
        (faultCounts["mDNSResponder"] ?? 0) >= dnsFaultThreshold
    }
}
