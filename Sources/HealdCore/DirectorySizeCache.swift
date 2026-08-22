import Foundation

/// Cache for recursive directory size so collectors never `du` huge trees every tick.
public struct DirectorySizeCache: Sendable {
    public var ttl: TimeInterval
    private var last: (at: Date, bytes: Int64)?

    public init(ttl: TimeInterval) {
        self.ttl = ttl
        self.last = nil
    }

    public mutating func bytes(
        at url: URL,
        now: Date = Date(),
        compute: (URL) -> Int64
    ) -> Int64 {
        if let last, now.timeIntervalSince(last.at) < ttl {
            return last.bytes
        }
        let value = compute(url)
        last = (now, value)
        return value
    }
}

public enum BootStampede: Sendable {
    public static func settled(uptime: TimeInterval, minimum: TimeInterval = 180) -> Bool {
        uptime >= minimum
    }
}

/// Downloading every `.icloud` placeholder fights Optimize Storage and
/// wakes FileProvider (FPCKService) into a CPU stampede.
public enum ICloudHealPolicy: Sendable {
    public static let cooldown: TimeInterval = 3600

    public static func shouldDownloadPlaceholders(
        evictedDirCount: Int,
        lastHeal: Date?,
        now: Date = Date(),
        cooldown: TimeInterval = cooldown
    ) -> Bool {
        guard evictedDirCount > 0 else { return false }
        if let lastHeal, now.timeIntervalSince(lastHeal) < cooldown { return false }
        return true
    }
}
