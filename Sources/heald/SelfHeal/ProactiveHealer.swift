import Foundation
import OSLog

/// Proactive hygiene — native (inspired by meisterSiri heal, not calling it).
struct ProactiveHealer: Sendable {
    func run(activityLog: ActivityLog) async {
        var fixes = 0
        fixes += removeBrokenSymlinks(in: [
            "\(NSHomeDirectory())/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
        ])
        await AutofixEngine().quarantineOrphanAgents(activityLog: activityLog)
        // Desktop only — Documents/Developer full-tree finds at login starve Spotlight.
        fixes += cleanDSStore(in: [
            "\(NSHomeDirectory())/Desktop",
        ])

        if fixes > 0 {
            try? await activityLog.log(event: ActivityEvent(
                type: .selfHealed,
                summary: "Proactive heal: \(fixes) local fix(es)"
            ))
            Logger.healer.info("Proactive heal applied \(fixes) fix(es)")
        } else {
            Logger.healer.debug("Proactive heal: nothing to do")
        }
    }

    private func removeBrokenSymlinks(in dirs: [String]) -> Int {
        var n = 0
        let fm = FileManager.default
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for name in items {
                let path = (dir as NSString).appendingPathComponent(name)
                // is symlink?
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      attrs[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
                guard let dest = try? fm.destinationOfSymbolicLink(atPath: path) else { continue }
                let target: String
                if dest.hasPrefix("/") {
                    target = dest
                } else {
                    target = (dir as NSString).appendingPathComponent(dest)
                }
                if !fm.fileExists(atPath: target) {
                    try? fm.removeItem(atPath: path)
                    n += 1
                    Logger.healer.info("Removed broken symlink: \(path)")
                }
            }
        }
        return n
    }

    private func cleanDSStore(in dirs: [String]) -> Int {
        var n = 0
        for dir in dirs {
            guard FileManager.default.fileExists(atPath: dir) else { continue }
            let r = ShellRunner.run("/usr/bin/find", arguments: [
                dir, "-maxdepth", "2", "-name", ".DS_Store", "-type", "f",
            ], timeoutSeconds: 8)
            for line in r.output.split(separator: "\n") {
                let p = String(line)
                guard !p.isEmpty else { continue }
                try? FileManager.default.removeItem(atPath: p)
                n += 1
            }
        }
        return n
    }
}
