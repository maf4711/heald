import Foundation
import ServiceLifecycle
import OSLog

struct ProcessCollector: Service {
    let store: MetricsStore

    func run() async throws {
        try await withGracefulShutdownHandler {
            while true {
                let (byCPU, byRAM) = collectProcesses()

                let snapshot = ProcessSnapshot(
                    byCPU: byCPU,
                    byRAM: byRAM,
                    timestamp: Date()
                )
                await store.updateProcesses(snapshot)

                Logger.collector.debug(
                    "Processes: \(byCPU.count + byRAM.count) total, top CPU=\(byCPU.first?.name ?? "none") \(byCPU.first?.cpuPercent ?? 0)%"
                )

                try await Task.sleep(for: .seconds(5))
            }
        } onGracefulShutdown: {
            // Task.sleep throws CancellationError on shutdown, breaking the while loop cleanly.
        }
    }

    // MARK: - Private collection helpers

    private func collectProcesses() -> ([ProcessEntry], [ProcessEntry]) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -A: all processes, -c: show abbreviated process names
        // -e: show environment variables in output (needed for -o)
        // -o: custom output format
        // -r: sort by CPU descending
        task.arguments = ["-Aceo", "pid,pcpu,rss,uid,comm", "-r"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()  // suppress stderr

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            Logger.collector.error("ps failed to launch: \(error)")
            return ([], [])
        }

        guard task.terminationStatus == 0 else {
            Logger.collector.error("ps exited with code \(task.terminationStatus)")
            return ([], [])
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
            Logger.collector.warning("ps produced empty output")
            return ([], [])
        }

        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 1 else {
            Logger.collector.warning("ps output has no data rows")
            return ([], [])
        }

        var entries: [ProcessEntry] = []

        // Skip the first line (header)
        for line in lines.dropFirst() {
            let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count >= 5 else { continue }

            guard let pid = Int32(parts[0]) else { continue }

            // CRITICAL: replace "," with "." for locale safety (German locale uses comma decimal separator)
            let cpuString = parts[1].replacingOccurrences(of: ",", with: ".")
            guard let cpuPercent = Double(cpuString) else { continue }

            guard let rssKB = Int64(parts[2]) else { continue }
            guard let uid = Int(parts[3]) else { continue }

            let name = String(parts[4])
            let ramBytes = rssKB * 1024  // ps reports RSS in kilobytes
            let isSystem = uid < 500     // MON-06: system processes tagged for Phase 5 safelist

            entries.append(ProcessEntry(
                pid: pid,
                name: name,
                cpuPercent: cpuPercent,
                ramBytes: ramBytes,
                uid: uid,
                isSystem: isSystem
            ))
        }

        // byCPU: ps -r already sorts by %CPU descending — take first 25
        let byCPU = Array(entries.prefix(25))

        // byRAM: sort by ramBytes descending, take first 25
        let byRAM = Array(
            entries.sorted { $0.ramBytes > $1.ramBytes }.prefix(25)
        )

        return (byCPU, byRAM)
    }
}
