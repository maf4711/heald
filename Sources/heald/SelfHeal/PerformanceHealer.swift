import Darwin
import Foundation
import HealdCore
import OSLog

/// When the Mac is not performing, apply the same safe local heals used
/// in the 2026-08-22 boot-stampede incident: Spotlight exclude heavy
/// trees, strip RunAtLoad from interval agents, drop Debug login items,
/// stop runaway `du ~/Documents`. No sudo, no Spotlight rebuild, no
/// BlockBlock/FileVault changes.
struct PerformanceHealer: Sendable {
    struct Report: Sendable {
        var skippedHealthy = false
        var spotlightExcluded: [String] = []
        var runAtLoadStripped: [String] = []
        var debugLoginItemsRemoved: [String] = []
        var runawayDuKilled: [Int32] = []
        var cpuStormKilled: [(Int32, String)] = []

        var didWork: Bool {
            !spotlightExcluded.isEmpty
                || !runAtLoadStripped.isEmpty
                || !debugLoginItemsRemoved.isEmpty
                || !runawayDuKilled.isEmpty
                || !cpuStormKilled.isEmpty
        }
    }

    func run(activityLog: ActivityLog, cpuOverall: Double, force: Bool) async -> Report {
        let load1 = Self.loadAverage1()
        let ncpu = ProcessInfo.processInfo.activeProcessorCount
        let uptime = ProcessInfo.processInfo.systemUptime
        let degraded = PerformanceAutoheal.isDegraded(
            load1: load1, ncpu: ncpu, cpuOverall: cpuOverall, uptime: uptime
        )
        if !force && !degraded {
            Logger.healer.debug("perf autoheal: healthy load=\(load1, format: .fixed(precision: 2)) ncpu=\(ncpu)")
            return Report(skippedHealthy: true)
        }

        var report = Report()
        report.cpuStormKilled = healCpuStormSync()
        report.spotlightExcluded = excludeSpotlightHeavyDirs()
        report.runAtLoadStripped = stripIntervalRunAtLoad()
        report.debugLoginItemsRemoved = removeDebugLoginItems()
        report.runawayDuKilled = killRunawayDocumentsDu()

        if report.didWork {
            let summary = "perf autoheal load=\(String(format: "%.1f", load1))/\(ncpu) spotlight=\(report.spotlightExcluded.count) runAtLoad=\(report.runAtLoadStripped.count) debugLogin=\(report.debugLoginItemsRemoved.count) du=\(report.runawayDuKilled.count) cpuStorm=\(report.cpuStormKilled.count)"
            try? await activityLog.log(event: ActivityEvent(
                type: .selfHealed,
                summary: summary,
                detail: "spotlight=\(report.spotlightExcluded.joined(separator: ",")) agents=\(report.runAtLoadStripped.joined(separator: ",")) login=\(report.debugLoginItemsRemoved.joined(separator: ","))"
            ))
            Logger.healer.info("\(summary)")
        } else {
            Logger.healer.info("perf autoheal: degraded but nothing left to fix (load=\(load1, format: .fixed(precision: 2)))")
        }
        return report
    }

    static func loadAverage1() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        let n = getloadavg(&loads, 3)
        guard n > 0 else { return 0 }
        return loads[0]
    }

    /// Always-on CPU storm heal (HUD dupes / leaked it2). Runs even when
    /// load is not fully degraded and even when bank consent=log.
    func healCpuStorm(activityLog: ActivityLog) async -> [(Int32, String)] {
        let killed = healCpuStormSync()
        if !killed.isEmpty {
            let detail = killed.map { "\($0.1):\($0.0)" }.joined(separator: ",")
            try? await activityLog.log(event: ActivityEvent(
                type: .selfHealed,
                summary: "cpu storm heal \(detail)",
                detail: detail
            ))
        }
        return killed
    }

    private func healCpuStormSync() -> [(Int32, String)] {
        let load1 = Self.loadAverage1()
        writePressure(load1 >= CpuStorm.pressureLoad)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let holdURL = home.appendingPathComponent(".cache/cpu-guard.hold")
        let holdMtime = (try? holdURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)
        let hold = CpuStorm.holdActive(now: Date(), holdMtime: holdMtime)
        let hudPid = readHudPidfile()
        let procs = listStormProcs()
        let planned = CpuStorm.plan(procs: procs, hold: hold, hudPidfile: hudPid)
        var killed: [(Int32, String)] = []
        for (pid, reason) in planned {
            guard pid != getpid(), pid != getppid() else { continue }
            kill(pid, SIGTERM)
            usleep(150_000)
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
            killed.append((pid, reason))
            Logger.healer.warning("cpu storm: kill pid=\(pid) reason=\(reason, privacy: .public)")
        }
        return killed
    }

    private func writePressure(_ on: Bool) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/cpu-guard.pressure")
        if on {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? "load1=\(Self.loadAverage1())\n".write(to: url, atomically: true, encoding: .utf8)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func readHudPidfile() -> Int32? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/claude/statusline-daemon.pid")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Int32(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func listStormProcs() -> [CpuStorm.Proc] {
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        let ps = ShellRunner.run(
            "/bin/ps",
            arguments: ["-axo", "pid=,etime=,command="],
            environment: env,
            timeoutSeconds: 8
        )
        guard ps.succeeded else { return [] }
        var out: [CpuStorm.Proc] = []
        for line in ps.output.split(separator: "\n") {
            let raw = line.trimmingCharacters(in: .whitespaces)
            let parts = raw.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]) else { continue }
            let etime = CpuStorm.parseEtime(String(parts[1]))
            let args = String(parts[2])
            out.append(CpuStorm.Proc(pid: pid, etime: etime, args: args, kind: CpuStorm.classify(args)))
        }
        return out
    }

    // MARK: - Spotlight

    private func excludeSpotlightHeavyDirs() -> [String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var done: [String] = []
        for rel in PerformanceAutoheal.spotlightExcludeRelative {
            let dir = home.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let marker = dir.appendingPathComponent(".metadata_never_index")
            if fm.fileExists(atPath: marker.path) { continue }
            fm.createFile(atPath: marker.path, contents: Data())
            done.append(rel)
        }
        return done
    }

    // MARK: - LaunchAgents

    private func stripIntervalRunAtLoad() -> [String] {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [] }

        var stripped: [String] = []
        let uid = getuid()
        for plist in items where plist.pathExtension == "plist" {
            guard let dict = plistDict(plist) else { continue }
            let label = (dict["Label"] as? String)
                ?? plist.deletingPathExtension().lastPathComponent
            if PerformanceAutoheal.isProtectedAgentLabel(label) { continue }

            let runAtLoad = (dict["RunAtLoad"] as? Bool)
                ?? ((dict["RunAtLoad"] as? NSNumber)?.boolValue ?? false)
            let keepAlive = dict["KeepAlive"] != nil
            let interval = (dict["StartInterval"] as? Int)
                ?? (dict["StartInterval"] as? NSNumber)?.intValue
            guard PerformanceAutoheal.shouldStripRunAtLoad(
                runAtLoad: runAtLoad, keepAlive: keepAlive, startInterval: interval
            ) else { continue }

            let r = ShellRunner.run("/usr/bin/plutil", arguments: [
                "-replace", "RunAtLoad", "-bool", "false", plist.path,
            ], timeoutSeconds: 5)
            guard r.succeeded else { continue }

            _ = ShellRunner.run("/bin/launchctl", arguments: [
                "bootout", "gui/\(uid)/\(label)",
            ], timeoutSeconds: 5)
            _ = ShellRunner.run("/bin/launchctl", arguments: [
                "bootstrap", "gui/\(uid)", plist.path,
            ], timeoutSeconds: 5)
            stripped.append(label)
            Logger.healer.info("perf autoheal: RunAtLoad=false \(label)")
        }
        return stripped
    }

    // MARK: - Login items

    private func removeDebugLoginItems() -> [String] {
        let names = osascriptList("get the name of every login item")
        let paths = osascriptList("get the path of every login item")
        guard !names.isEmpty, names.count == paths.count else { return [] }

        var removed: [String] = []
        for (name, path) in zip(names, paths) {
            if PerformanceAutoheal.isProtectedLoginItem(name) { continue }
            guard PerformanceAutoheal.isDebugLoginItemPath(path) else { continue }
            let r = ShellRunner.run("/usr/bin/osascript", arguments: [
                "-e", "tell application \"System Events\" to delete login item \"\(name)\"",
            ], timeoutSeconds: 5)
            if r.succeeded {
                removed.append(name)
                Logger.healer.info("perf autoheal: removed Debug login item \(name)")
            }
        }
        return removed
    }

    // MARK: - runaway du

    private func killRunawayDocumentsDu() -> [Int32] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let ps = ShellRunner.run("/bin/ps", arguments: ["-axo", "pid=,comm=,args="], timeoutSeconds: 5)
        guard ps.succeeded else { return [] }

        var killed: [Int32] = []
        for line in ps.output.split(separator: "\n") {
            let raw = line.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { continue }
            let parts = raw.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count >= 3, let pid = Int32(parts[0]) else { continue }
            let comm = String(parts[1])
            guard comm == "du" || comm.hasSuffix("/du") else { continue }
            let args = String(parts[2]).split(separator: " ").map(String.init)
            guard PerformanceAutoheal.isRunawayDocumentsDu(arguments: args, home: home) else { continue }
            _ = ShellRunner.run("/bin/kill", arguments: ["-TERM", String(pid)])
            killed.append(pid)
            Logger.healer.info("perf autoheal: SIGTERM du pid=\(pid)")
        }
        return killed
    }

    // MARK: - plist / osascript helpers

    private func plistDict(_ url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
    }

    private func osascriptList(_ query: String) -> [String] {
        let r = ShellRunner.run("/usr/bin/osascript", arguments: [
            "-e", "tell application \"System Events\" to \(query)",
        ], timeoutSeconds: 5)
        guard r.succeeded else { return [] }
        return r.output
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
