import Foundation

/// Last-fired timestamps per self-heal key (cooldown bookkeeping for `SelfHealOrchestrator.fire`).
actor HealCooldownState {
    private var last: [String: Date] = [:]

    func canFire(key: String, cooldown: TimeInterval) -> Bool {
        guard let t = last[key] else { return true }
        return Date().timeIntervalSince(t) >= cooldown
    }

    func markFired(key: String, at date: Date = Date()) {
        last[key] = date
    }

    func snapshot() -> [String: String] {
        let f = ISO8601DateFormatter()
        var out: [String: String] = [:]
        for (k, v) in last {
            out[k] = f.string(from: v)
        }
        return out
    }
}
