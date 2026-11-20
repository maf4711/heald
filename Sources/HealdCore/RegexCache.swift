import Foundation
import Synchronization

/// Compiled-once regexes (NSRegularExpression is immutable and thread-safe).
enum RegexCache {
    private struct Box: @unchecked Sendable { let re: NSRegularExpression }
    private static let cache = Mutex<[String: Box]>([:])

    static func regex(_ pattern: String) -> NSRegularExpression? {
        if let hit = cache.withLock({ $0[pattern] }) { return hit.re }
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        cache.withLock { $0[pattern] = Box(re: re) }
        return re
    }

    /// First capture group (or whole match when the pattern has no group).
    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let re = regex(pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        let r = m.numberOfRanges > 1 ? m.range(at: 1) : m.range
        guard let range = Range(r, in: s) else { return nil }
        return String(s[range])
    }

    static func replace(_ pattern: String, in s: String, with template: String) -> String {
        guard let re = regex(pattern) else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }
}

/// Token / secret redaction for anything that may leave the device (findings samples, cloud, SIEM).
public enum SecretRedactor {
    private static let rules: [(pattern: String, template: String)] = [
        (#"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer <token>"),
        (#"\b[0-9a-fA-F]{32,}\b"#, "<hex>"),
        // base64-ish run ≥ 40 with at least one digit and one letter (plain paths have no digits)
        (#"(?<![A-Za-z0-9+/_-])(?=[A-Za-z0-9+/_-]*[0-9])(?=[A-Za-z0-9+/_-]*[A-Za-z])[A-Za-z0-9+/_-]{40,}={0,2}"#, "<secret>"),
        (#"\b\d{10,}\b"#, "<id>"), // DSID-like long digit runs
    ]

    public static func redact(_ s: String) -> String {
        rules.reduce(s) { RegexCache.replace($1.pattern, in: $0, with: $1.template) }
    }
}
