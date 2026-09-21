import Foundation
import OSLog

/// Scans for git repositories with uncommitted or unpushed changes.
/// Reports status but does NOT auto-commit or auto-push (read-only audit).
struct GitRepoScanner {
    private let searchPaths = [
        "\(NSHomeDirectory())/Documents",
        "\(NSHomeDirectory())/Developer",
    ]
    private let maxDepth = 5
    private let cacheFile = "\(NSHomeDirectory())/.heald/git_repos.cache"
    private let cacheMaxAge: TimeInterval = 7 * 86400 // 7 days

    func scan(activityLog: ActivityLog) async -> [GitRepoStatus] {
        let repos = findRepos()
        var results: [GitRepoStatus] = []

        for repoDir in repos {
            guard let status = checkRepo(repoDir) else { continue }
            if status.dirtyFileCount > 0 || status.unpushedCommitCount > 0 {
                results.append(status)
            }
        }

        // Log summary
        let dirty = results.filter { $0.dirtyFileCount > 0 }
        let unpushed = results.filter { $0.unpushedCommitCount > 0 }

        if !dirty.isEmpty {
            Logger.health.warning("Git: \(dirty.count) repos with uncommitted changes")
        }
        if !unpushed.isEmpty {
            Logger.health.warning("Git: \(unpushed.count) repos with unpushed commits")
        }

        if !results.isEmpty {
            let detail = results.map { repo in
                var parts = [repo.name]
                if repo.dirtyFileCount > 0 { parts.append("\(repo.dirtyFileCount) dirty") }
                if repo.unpushedCommitCount > 0 { parts.append("\(repo.unpushedCommitCount) unpushed") }
                return parts.joined(separator: ": ")
            }.joined(separator: "\n")

            try? await activityLog.log(event: ActivityEvent(
                type: .gitReposDirty,
                summary: "Git: \(dirty.count) dirty, \(unpushed.count) unpushed repos",
                detail: detail
            ))
        }

        Logger.health.info("Git scan: \(repos.count) repos found, \(results.count) need attention")
        return results
    }

    private func findRepos() -> [String] {
        // Check cache
        if let cacheData = FileManager.default.contents(atPath: cacheFile),
           let cacheContent = String(data: cacheData, encoding: .utf8),
           let attrs = try? FileManager.default.attributesOfItem(atPath: cacheFile),
           let modDate = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) < cacheMaxAge {
            return cacheContent.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        }

        // Fresh scan
        var repos: [String] = []
        for searchPath in searchPaths {
            guard FileManager.default.fileExists(atPath: searchPath) else { continue }

            let result = ShellRunner.run("/usr/bin/find", arguments: [
                searchPath, "-maxdepth", "\(maxDepth)",
                "-name", ".git", "-type", "d",
                "-not", "-path", "*/node_modules/*",
                "-not", "-path", "*/.Trash/*",
                "-not", "-path", "*/Backups/*",
            ])

            if result.succeeded {
                for line in result.output.split(separator: "\n") {
                    let gitDir = String(line)
                    let repoDir = (gitDir as NSString).deletingLastPathComponent
                    repos.append(repoDir)
                }
            }
        }

        // Save cache
        let cacheDir = (cacheFile as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        try? repos.joined(separator: "\n").write(toFile: cacheFile, atomically: true, encoding: .utf8)

        return repos
    }

    private func checkRepo(_ repoDir: String) -> GitRepoStatus? {
        guard let gitPath = ShellRunner.findExecutable("git") else { return nil }

        // Get branch name
        let branchResult = ShellRunner.run(gitPath, arguments: [
            "-C", repoDir, "rev-parse", "--abbrev-ref", "HEAD"
        ])
        guard branchResult.succeeded else { return nil }
        let branch = branchResult.output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check dirty status
        let statusResult = ShellRunner.run(gitPath, arguments: [
            "-C", repoDir, "status", "--porcelain"
        ])
        let dirtyCount = statusResult.succeeded
            ? statusResult.output.split(separator: "\n").filter({ !$0.isEmpty }).count
            : 0

        // Check unpushed commits
        var unpushedCount = 0
        let upstreamResult = ShellRunner.run(gitPath, arguments: [
            "-C", repoDir, "rev-parse", "--abbrev-ref", "\(branch)@{upstream}"
        ])
        if upstreamResult.succeeded {
            let upstream = upstreamResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            let logResult = ShellRunner.run(gitPath, arguments: [
                "-C", repoDir, "log", "\(upstream)..HEAD", "--oneline"
            ])
            if logResult.succeeded {
                unpushedCount = logResult.output.split(separator: "\n").filter({ !$0.isEmpty }).count
            }
        }

        let name = (repoDir as NSString).lastPathComponent
        return GitRepoStatus(
            path: repoDir, name: name, branch: branch,
            dirtyFileCount: dirtyCount, unpushedCommitCount: unpushedCount
        )
    }
}
