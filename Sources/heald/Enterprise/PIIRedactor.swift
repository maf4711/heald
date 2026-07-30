import Foundation

/// Redact likely PII before leaving the device (cloud / SIEM).
enum PIIRedactor {
    /// Home directory path for current user.
    private static var home: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static var user: String { NSUserName() }

    static func redact(_ text: String) -> String {
        var s = text
        // Full home path first
        if !home.isEmpty {
            s = s.replacingOccurrences(of: home, with: "~")
            s = s.replacingOccurrences(of: "/Users/\(user)", with: "/Users/<redacted>")
        }
        // Generic /Users/name
        if let regex = try? NSRegularExpression(pattern: #"/Users/[^/\s]+"#, options: []) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "/Users/<redacted>")
        }
        // Email-ish
        if let regex = try? NSRegularExpression(
            pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "<email>")
        }
        // IPv4 (keep private ranges? redact all outbound for bank tier)
        if let regex = try? NSRegularExpression(pattern: #"\b\d{1,3}(\.\d{1,3}){3}\b"#) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "<ip>")
        }
        return s
    }

    static func redactEventDict(_ dict: [String: Any]) -> [String: Any] {
        var out = dict
        for key in ["summary", "detail", "beforeState", "afterState", "hostname"] {
            if let v = out[key] as? String {
                out[key] = redact(v)
            }
        }
        return out
    }
}
