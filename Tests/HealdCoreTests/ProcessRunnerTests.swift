import Foundation
import Testing
@testable import HealdCore

struct ProcessRunnerTests {
    /// > 64 KB on stdout used to deadlock: the pipe filled while the runner only polled for exit.
    @Test func drainsLargeStdoutWithoutDeadlock() {
        let start = Date()
        let r = ProcessRunner.run(
            "/bin/sh", arguments: ["-c", "/usr/bin/yes x | /usr/bin/head -c 200000"], timeoutSeconds: 5
        )
        #expect(r.exitCode == 0)
        #expect(r.output.utf8.count == 200_000)
        #expect(Date().timeIntervalSince(start) < 4)
    }

    @Test func drainsLargeStderrConcurrently() {
        let r = ProcessRunner.run(
            "/bin/sh", arguments: ["-c", "/usr/bin/yes e | /usr/bin/head -c 150000 >&2; echo done"], timeoutSeconds: 5
        )
        #expect(r.exitCode == 0)
        #expect(r.errorOutput.utf8.count == 150_000)
        #expect(r.output == "done\n")
    }

    @Test func timeoutReturns124WithPartialOutput() {
        let r = ProcessRunner.run("/bin/sh", arguments: ["-c", "echo early; sleep 30"], timeoutSeconds: 0.5)
        #expect(r.exitCode == 124)
        #expect(r.output.hasPrefix("early"))
    }

    @Test func launchFailureIsMinusOne() {
        #expect(ProcessRunner.run("/nonexistent/binary").exitCode == -1)
    }
}
