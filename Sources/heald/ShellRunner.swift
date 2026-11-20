import Foundation
import HealdCore

/// Utility for running shell commands from maintenance modules.
enum ShellRunner {
    struct Result: Sendable {
        let output: String
        let errorOutput: String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    /// Delegates to `HealdCore.ProcessRunner`, which drains stdout/stderr while the child runs
    /// (outputs > 64 KB such as `launchctl print` used to deadlock until the timeout).
    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) -> Result {
        let r = ProcessRunner.run(
            executable, arguments: arguments, environment: environment, timeoutSeconds: timeoutSeconds
        )
        return Result(output: r.output, errorOutput: r.errorOutput, exitCode: r.exitCode)
    }

    /// Find executable in common paths.
    static func findExecutable(_ name: String) -> String? {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin"]
        for dir in paths {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
