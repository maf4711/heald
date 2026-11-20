import Foundation

/// Pure parsers turning raw log inputs into `Observation`s. `nil` means unparseable.
extension DiagnosisEngine {
    /// Diagnostic report (.ips / .crash / .diag / .panic) → crash, panic or resource fault.
    public static func classifyReport(filename: String, contents: String, at: Date) -> Observation? {
        guard !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let sample = String(contents.prefix(Finding.maxSample))

        let isPanicBug = firstMatch(#""bug_type"\s*:\s*"210""#, in: contents) != nil
        let isPanicFile = filename.lowercased().hasSuffix(".panic") || filename.lowercased().hasPrefix("panic")
        if isPanicBug || isPanicFile {
            let reason = firstMatch(#"panic\(cpu[^)]*\)\s*:?\s*([^"\n\\]+)"#, in: contents).map(normalizePanic)
            guard let signature = reason ?? (isPanicBug ? "unknown" : nil), !signature.isEmpty else { return nil }
            return Observation(
                category: .panic, component: "kernel", signature: signature,
                source: .panicReport, at: at, sample: sample
            )
        }

        let component = reportComponent(filename: filename, contents: contents)
        guard !component.isEmpty else { return nil }

        if let exception = firstMatch(#""exception"\s*:\s*\{[^}]*?"type"\s*:\s*"([^"]+)""#, in: contents)
            ?? firstMatch(#"(?m)^Exception Type:\s*(\S+)"#, in: contents) {
            return Observation(
                category: .crash, component: component, signature: exception,
                source: .crashReport, at: at, sample: sample
            )
        }
        if let event = firstMatch(#"(?m)^Event:\s*(.+?)\s*$"#, in: contents) {
            let signature = event.lowercased()
                .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            guard !signature.isEmpty else { return nil }
            return Observation(
                category: .fault, component: component, signature: cap(signature, Finding.maxShort),
                source: .diagnosticReport, at: at, sample: sample
            )
        }
        return nil
    }

    /// `log show --style compact` line: `2026-11-20 10:15:00.123 Fa  proc[pid:tid] msg`.
    public static func classifyFaultLine(_ line: String, at: Date) -> Observation? {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count >= 4, firstMatch(#"^(\d{4}-\d{2}-\d{2})$"#, in: String(parts[0])) != nil else {
            return nil
        }
        var token = String(parts[3])
        if let bracket = token.firstIndex(of: "[") { token = String(token[..<bracket]) }
        if token.hasSuffix(":") { token = String(token.dropLast()) }
        guard !token.isEmpty else { return nil }
        return Observation(
            category: .fault, component: token, signature: "",
            source: .unifiedLog, at: at, sample: String(line.prefix(Finding.maxSample))
        )
    }

    /// `launchctl print gui/<uid>` services block → failing jobs (label → last exit status).
    /// Rule ported from daemon-ops-mcp `daemon_health`: last exit != 0; SIGTERM on unload (-15) is not a failure.
    public static func launchdFailures(from output: String) -> [String: Int] {
        var out: [String: Int] = [:]
        var inServices = false
        for raw in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "services = {" { inServices = true; continue }
            guard inServices else { continue }
            if line == "}" { inServices = false; continue }
            let cols = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard cols.count == 3, cols[0] == "-" || Int(cols[0]) != nil,
                  let code = Int(cols[1]), code != 0, code != -15 else { continue }
            out[String(cols[2])] = code
        }
        return out
    }

    /// `Finder-2026-11-20-101500.ips` / `bird_2026-11-20-111520_host.diag` → process name.
    public static func processName(fromReportFilename name: String) -> String {
        let base = (name as NSString).deletingPathExtension
        guard let r = base.range(of: #"[-_]\d{4}-\d{2}-\d{2}.*$"#, options: .regularExpression) else { return base }
        return String(base[..<r.lowerBound])
    }

    private static func reportComponent(filename: String, contents: String) -> String {
        let fromName = processName(fromReportFilename: (filename as NSString).lastPathComponent)
        if !fromName.isEmpty { return fromName }
        return firstMatch(#""(?:procName|app_name)"\s*:\s*"([^"]+)""#, in: contents)
            ?? firstMatch(#"(?m)^(?:Process|Command):\s*(\S+)"#, in: contents)
            ?? ""
    }

    /// Strip addresses/numbers so the same panic on another boot keeps its fingerprint.
    private static func normalizePanic(_ s: String) -> String {
        let t = s
            .replacingOccurrences(of: #"0x[0-9a-fA-F]+"#, with: "0x", options: .regularExpression)
            .replacingOccurrences(of: #"\d+"#, with: "#", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return cap(redactPaths(t), 80)
    }

    /// First capture group (or whole match when the pattern has no group).
    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        let r = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
        guard let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }
}
