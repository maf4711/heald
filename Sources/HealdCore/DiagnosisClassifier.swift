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
            // Message may be quoted, JSON-escaped (\"…\") or bare; a panic file is never unparsed.
            let reason = firstMatch(#"panic\(cpu[^)]*\)\s*:?\s*(?:\\?")?([^"\n\\]+)"#, in: contents)
                .map(normalizePanic) ?? ""
            let signature = reason.isEmpty ? "unknown" : reason
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
            let signature = RegexCache.replace(#"[^a-z0-9]+"#, in: event.lowercased(), with: "_")
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
        var t = RegexCache.replace(#"0x[0-9a-fA-F]+"#, in: s, with: "0x")
        t = RegexCache.replace(#"\d+"#, in: t, with: "#")
        t = RegexCache.replace(#"\s+"#, in: t, with: " ").trimmingCharacters(in: .whitespaces)
        return cap(redactPaths(t), 80)
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        RegexCache.firstMatch(pattern, in: s)
    }
}
