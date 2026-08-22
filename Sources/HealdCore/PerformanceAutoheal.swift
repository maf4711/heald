import Foundation

/// Policy for Mac performance autoheal. Pure — no shell, no filesystem.
/// Applied by heald when load/CPU says the machine is not performing.
public enum PerformanceAutoheal: Sendable {
    /// First 10 minutes after boot: half-core load is already a stampede.
    public static let bootWindow: TimeInterval = 600
    public static let bootLoadPerCore = 0.50
    public static let steadyLoadPerCore = 0.85
    public static let cpuOverallLimit = 0.75

    public static func isDegraded(
        load1: Double,
        ncpu: Int,
        cpuOverall: Double,
        uptime: TimeInterval
    ) -> Bool {
        guard ncpu > 0 else { return false }
        let cores = Double(ncpu)
        let loadLimit = uptime < bootWindow ? cores * bootLoadPerCore : cores * steadyLoadPerCore
        if load1 >= loadLimit { return true }
        if cpuOverall >= cpuOverallLimit { return true }
        return false
    }

    /// Interval jobs (StartInterval) must not also RunAtLoad — that is the
    /// login pile-up (Mail auto, repo-sync). KeepAlive daemons stay.
    public static func shouldStripRunAtLoad(
        runAtLoad: Bool,
        keepAlive: Bool,
        startInterval: Int?
    ) -> Bool {
        guard runAtLoad, !keepAlive else { return false }
        guard let startInterval, startInterval >= 60 else { return false }
        return true
    }

    public static func isProtectedAgentLabel(_ label: String) -> Bool {
        let l = label.lowercased()
        let prefixes = [
            "com.heald", "ai.openclaw", "ai.fbrk", "com.maccluster",
            "homebrew.mxcl", "com.meister",
        ]
        return prefixes.contains { l.hasPrefix($0) }
    }

    public static func isDebugLoginItemPath(_ path: String) -> Bool {
        if path.contains("/DerivedData/") { return true }
        if path.contains("/Build/Products/Debug/") { return true }
        return false
    }

    public static func isProtectedLoginItem(_ name: String) -> Bool {
        let n = name.lowercased()
        let protect = [
            "wispr", "swiftbar", "stats", "raycast", "iterm", "ghostty",
            "tailscale", "blockblock", "lulu", "knockknock",
        ]
        return protect.contains { n.contains($0) }
    }

    public static func isRunawayDocumentsDu(arguments: [String], home: String) -> Bool {
        let docs = (home as NSString).appendingPathComponent("Documents")
        return arguments.contains { $0 == docs || $0.hasPrefix(docs + "/") }
    }

    public static let spotlightExcludeRelative = [
        "Developer",
        "Library/Developer",
        "go",
        "miniforge3",
        "Venvs",
        ".ollama",
        ".cargo",
        ".rustup",
        ".npm",
        ".gradle",
        ".docker",
    ]
}
