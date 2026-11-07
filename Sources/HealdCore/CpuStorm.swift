import Foundation

/// CPU storm policy: HUD daemon dupes, leaked it2, stuck statusline npm.
/// Pure — no shell, no kill. Applied by heald PerformanceHealer every tick.
///
/// 2026-08-23: three statusline retry daemons stole the HUD lock and pinned
/// iTerm; heald's bank `consent=log` only recorded BLOCKED and never healed.
public enum CpuStorm: Sendable {
    public static let maxIt2 = 4
    public static let npmAgeSec = 15
    public static let settingsAgeSec = 120
    public static let maxShowBuild = 2
    public static let pressureLoad = 8.0
    public static let holdHudMelt = 5
    public static let holdIt2Melt = 20
    public static let holdMaxAge: TimeInterval = 6 * 3600

    public enum Kind: String, Sendable, Equatable {
        case hudDaemon
        case it2
        case statuslineNpm
        case showBuildSettings
    }

    public struct Proc: Sendable, Equatable {
        public let pid: Int32
        public let etime: Int
        public let args: String
        public let kind: Kind?

        public init(pid: Int32, etime: Int, args: String, kind: Kind?) {
            self.pid = pid
            self.etime = etime
            self.args = args
            self.kind = kind
        }
    }

    public static func cmdBase(_ args: String) -> String {
        let first = args.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
        return (first as NSString).lastPathComponent
    }

    public static func classify(_ args: String) -> Kind? {
        if args.contains("cpu-guard.py") || args.contains("CpuStorm") { return nil }
        let base = cmdBase(args)
        if ["bash", "sh"].contains(base), args.contains("statusline-daemon.lockdir") {
            return .hudDaemon
        }
        if ["bash", "sh"].contains(base),
           args.contains("statusline-daemon.sh"),
           args.contains("run-loop") {
            return .hudDaemon
        }
        if base == "statusline-daemon.sh", args.contains("run-loop") {
            return .hudDaemon
        }
        if base == "it2" { return .it2 }
        if ["npm", "node", "npx"].contains(base),
           args.contains("hooks statusline")
            || (args.contains("@claude-flow/cli") && args.contains("statusline")) {
            return .statuslineNpm
        }
        if base == "xcodebuild", args.contains("-showBuildSettings") {
            return .showBuildSettings
        }
        return nil
    }

    public static func parseEtime(_ raw: String) -> Int {
        var s = raw.trimmingCharacters(in: .whitespaces)
        var days = 0
        if let dash = s.firstIndex(of: "-") {
            days = Int(s[s.startIndex..<dash]) ?? 0
            s = String(s[s.index(after: dash)...])
        }
        let parts = s.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return days * 86_400 + parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2: return days * 86_400 + parts[0] * 60 + parts[1]
        case 1: return days * 86_400 + parts[0]
        default: return 0
        }
    }

    public static func extrasToKill(
        _ group: [Proc],
        keepPid: Int32?,
        maxKeep: Int,
        preferOldest: Bool
    ) -> [Proc] {
        guard maxKeep >= 0 else { return [] }
        let ordered = preferOldest
            ? group.sorted { ($0.etime, Int($0.pid)) > ($1.etime, Int($1.pid)) }
            : group.sorted { ($0.etime, Int($0.pid)) < ($1.etime, Int($1.pid)) }
        if let keepPid, ordered.contains(where: { $0.pid == keepPid }) {
            let rest = ordered.filter { $0.pid != keepPid }
            let skip = max(0, maxKeep - 1)
            return Array(rest.dropFirst(skip))
        }
        if ordered.count <= maxKeep { return [] }
        return Array(ordered.dropFirst(maxKeep))
    }

    public static func plan(
        procs: [Proc],
        hold: Bool,
        hudPidfile: Int32?,
        maxIt2: Int = maxIt2,
        npmAge: Int = npmAgeSec,
        settingsAge: Int = settingsAgeSec,
        maxShowBuild: Int = maxShowBuild
    ) -> [(Int32, String)] {
        let hud = procs.filter { $0.kind == .hudDaemon }
        let it2 = procs.filter { $0.kind == .it2 }
        let npm = procs.filter { $0.kind == .statuslineNpm }
        let settings = procs.filter { $0.kind == .showBuildSettings }
        let melt = hud.count >= holdHudMelt || it2.count >= holdIt2Melt
        if hold && !melt { return [] }

        var kills: [(Int32, String)] = []
        let keepHud = hud.contains(where: { $0.pid == hudPidfile }) ? hudPidfile : nil
        for p in extrasToKill(hud, keepPid: keepHud, maxKeep: 1, preferOldest: true) {
            kills.append((p.pid, "hud_dup"))
        }
        for p in extrasToKill(it2, keepPid: nil, maxKeep: maxIt2, preferOldest: false) {
            kills.append((p.pid, "it2_flood"))
        }
        for p in extrasToKill(settings, keepPid: nil, maxKeep: maxShowBuild, preferOldest: false) {
            kills.append((p.pid, "showBuildSettings"))
        }
        for p in npm where p.etime >= npmAge {
            kills.append((p.pid, "statusline_npm"))
        }
        for p in settings where p.etime >= settingsAge {
            kills.append((p.pid, "showBuildSettings"))
        }
        var seen = Set<Int32>()
        var out: [(Int32, String)] = []
        for (pid, reason) in kills {
            guard pid > 1, !seen.contains(pid) else { continue }
            seen.insert(pid)
            out.append((pid, reason))
        }
        return out
    }

    public static func holdActive(now: Date, holdMtime: Date?) -> Bool {
        guard let holdMtime else { return false }
        let age = now.timeIntervalSince(holdMtime)
        return age >= 0 && age < holdMaxAge
    }
}
