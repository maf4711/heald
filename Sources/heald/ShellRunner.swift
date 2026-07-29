import Foundation

/// Utility for running shell commands from maintenance modules.
enum ShellRunner {
    struct Result: Sendable {
        let output: String
        let errorOutput: String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) -> Result {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        if let env = environment { task.environment = env }

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe

        do {
            try task.run()
        } catch {
            return Result(output: "", errorOutput: error.localizedDescription, exitCode: -1)
        }

        if let timeout = timeoutSeconds, timeout > 0 {
            let deadline = Date().addingTimeInterval(timeout)
            while task.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if task.isRunning {
                task.terminate()
                // brief wait then force-kill if needed
                Thread.sleep(forTimeInterval: 0.2)
                if task.isRunning { task.interrupt() }
                return Result(
                    output: String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                    errorOutput: "timeout after \(Int(timeout))s",
                    exitCode: 124
                )
            }
        } else {
            task.waitUntilExit()
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        return Result(
            output: String(data: outData, encoding: .utf8) ?? "",
            errorOutput: String(data: errData, encoding: .utf8) ?? "",
            exitCode: task.terminationStatus
        )
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
