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
        environment: [String: String]? = nil
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

        task.waitUntilExit()

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
