import Foundation

/// Runs a subprocess and drains stdout/stderr **while** it runs.
/// Reading only after exit deadlocks once a child writes more than the pipe buffer (64 KB):
/// the child blocks on write, never exits, and the caller times out (e.g. `launchctl print`, `log show`).
public enum ProcessRunner {
    public struct Output: Sendable {
        public let output: String
        public let errorOutput: String
        public let exitCode: Int32
    }

    /// Thread-safe byte sink fed by a pipe's readability handler; `done` fires at EOF.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        let done = DispatchSemaphore(value: 0)

        func attach(_ handle: FileHandle) {
            handle.readabilityHandler = { [self] h in
                let chunk = h.availableData
                if chunk.isEmpty {
                    h.readabilityHandler = nil
                    done.signal()
                } else {
                    lock.withLock { data.append(chunk) }
                }
            }
        }

        var string: String { lock.withLock { String(decoding: data, as: UTF8.self) } }
    }

    public static func run(
        _ executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeoutSeconds: TimeInterval? = nil
    ) -> Output {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        if let env = environment { task.environment = env }

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        let out = Sink()
        let err = Sink()
        out.attach(outPipe.fileHandleForReading)
        err.attach(errPipe.fileHandleForReading)

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }

        do {
            try task.run()
        } catch {
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            return Output(output: "", errorOutput: error.localizedDescription, exitCode: -1)
        }

        var timedOut = false
        if let timeout = timeoutSeconds, timeout > 0 {
            if exited.wait(timeout: .now() + timeout) == .timedOut {
                timedOut = true
                task.terminate()
                if exited.wait(timeout: .now() + 0.5) == .timedOut {
                    kill(task.processIdentifier, SIGKILL)
                    _ = exited.wait(timeout: .now() + 0.5)
                }
            }
        } else {
            exited.wait()
        }

        // Grandchildren may hold the pipe open after a kill: bound the EOF wait, keep partial output.
        let eofWait: DispatchTime = .now() + (timedOut ? 0.5 : 2)
        _ = out.done.wait(timeout: eofWait)
        _ = err.done.wait(timeout: eofWait)
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        if timedOut {
            return Output(
                output: out.string,
                errorOutput: "timeout after \(Int(timeoutSeconds ?? 0))s",
                exitCode: 124
            )
        }
        return Output(output: out.string, errorOutput: err.string, exitCode: task.terminationStatus)
    }
}
