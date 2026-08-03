import Foundation

/// One-shot approvals for `consent=ask` — written by `heald approve <action>`.
enum ApprovalStore {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/approvals.json")
    }

    /// If a non-expired approval exists for `action`, consume it and return true.
    static func consume(action: String) -> Bool {
        guard var dict = load(),
              let expStr = dict[action] as? String,
              let exp = ISO8601DateFormatter().date(from: expStr),
              exp > Date() else {
            return false
        }
        dict.removeValue(forKey: action)
        save(dict)
        return true
    }

    private static func load() -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return obj
    }

    private static func save(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }
}
