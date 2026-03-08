import Foundation
import OSLog

/// Daily system benchmark measuring CPU, disk, and memory performance.
/// Runs at 02:00, takes ~30-60 seconds, stores results for trend tracking.
struct SystemBenchmark {

    // MARK: - Public API

    func runAll(activityLog: ActivityLog) async throws -> BenchmarkSnapshot {
        let start = Date()

        try? await activityLog.log(event: ActivityEvent(
            type: .benchmarkStarted,
            summary: "Daily system benchmark started"
        ))

        Logger.benchmark.info("Starting daily benchmark...")

        let coreCount = ProcessInfo.processInfo.activeProcessorCount

        // Run benchmarks sequentially to avoid interference
        let cpuSingle = await benchmarkCPUSingleCore()
        let cpuMulti = await benchmarkCPUMultiCore(cores: coreCount)
        let (diskWrite, diskRead) = await benchmarkDiskIO()
        let memBandwidth = await benchmarkMemoryBandwidth()

        let duration = Date().timeIntervalSince(start)

        let snapshot = BenchmarkSnapshot(
            cpuSingleCore: cpuSingle,
            cpuMultiCore: cpuMulti,
            diskWriteMBs: diskWrite,
            diskReadMBs: diskRead,
            memoryBandwidthGBs: memBandwidth,
            durationSeconds: duration,
            coreCount: coreCount,
            timestamp: Date()
        )

        let summary = "Benchmark complete: score \(snapshot.overallScore)/100 " +
            "(CPU-1: \(Int(cpuSingle)) ops/s, CPU-N: \(Int(cpuMulti)) ops/s, " +
            "Disk W: \(Int(diskWrite)) MB/s, R: \(Int(diskRead)) MB/s, " +
            "Mem: \(String(format: "%.1f", memBandwidth)) GB/s) in \(String(format: "%.1f", duration))s"

        try? await activityLog.log(event: ActivityEvent(
            type: .benchmarkCompleted,
            summary: summary,
            detail: "Cores: \(coreCount), Score: \(snapshot.overallScore)/100"
        ))

        Logger.benchmark.info("\(summary)")

        return snapshot
    }

    // MARK: - CPU Single-Core Benchmark

    /// Counts primes up to a fixed limit on a single core.
    private func benchmarkCPUSingleCore() async -> Double {
        let iterations = 3
        var totalOps: Double = 0

        for _ in 0..<iterations {
            let start = DispatchTime.now()
            let count = countPrimes(upTo: 100_000)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            totalOps += Double(count) / elapsed
        }

        return totalOps / Double(iterations)
    }

    // MARK: - CPU Multi-Core Benchmark

    /// Runs prime counting in parallel across all cores.
    private func benchmarkCPUMultiCore(cores: Int) async -> Double {
        let start = DispatchTime.now()

        let total = await withTaskGroup(of: Int.self, returning: Int.self) { group in
            for _ in 0..<cores {
                group.addTask {
                    countPrimes(upTo: 100_000)
                }
            }
            var sum = 0
            for await count in group { sum += count }
            return sum
        }

        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        return elapsed > 0 ? Double(total) / elapsed : 0
    }

    // MARK: - Disk I/O Benchmark

    /// Sequential write and read of a 256MB file.
    private func benchmarkDiskIO() async -> (writeMBs: Double, readMBs: Double) {
        let testSize = 256 * 1024 * 1024 // 256 MB
        let testPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".heald/benchmark_test.bin").path

        // Generate random data
        var data = Data(count: testSize)
        data.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            arc4random_buf(base, testSize)
        }

        // Write benchmark
        let writeStart = DispatchTime.now()
        FileManager.default.createFile(atPath: testPath, contents: data)
        let writeElapsed = Double(DispatchTime.now().uptimeNanoseconds - writeStart.uptimeNanoseconds) / 1_000_000_000
        let writeMBs = writeElapsed > 0 ? Double(testSize) / 1_048_576 / writeElapsed : 0

        // Read benchmark
        let readStart = DispatchTime.now()
        _ = FileManager.default.contents(atPath: testPath)
        let readElapsed = Double(DispatchTime.now().uptimeNanoseconds - readStart.uptimeNanoseconds) / 1_000_000_000
        let readMBs = readElapsed > 0 ? Double(testSize) / 1_048_576 / readElapsed : 0

        // Cleanup
        try? FileManager.default.removeItem(atPath: testPath)

        return (writeMBs, readMBs)
    }

    // MARK: - Memory Bandwidth Benchmark

    /// Measures memory copy throughput using large array operations.
    private func benchmarkMemoryBandwidth() async -> Double {
        let arraySize = 64 * 1024 * 1024 // 64M elements = 512 MB
        let iterations = 3
        var totalGBs: Double = 0

        for _ in 0..<iterations {
            let source = [UInt64](repeating: 0xDEADBEEF, count: arraySize)
            var dest = [UInt64](repeating: 0, count: arraySize)
            let byteCount = arraySize * MemoryLayout<UInt64>.size

            let start = DispatchTime.now()
            source.withUnsafeBufferPointer { srcBuf in
                dest.withUnsafeMutableBufferPointer { dstBuf in
                    _ = memcpy(dstBuf.baseAddress!, srcBuf.baseAddress!, byteCount)
                }
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000

            // Read + Write = 2x the data size transferred
            let gbTransferred = Double(byteCount) * 2 / 1_073_741_824
            totalGBs += elapsed > 0 ? gbTransferred / elapsed : 0

            // Prevent optimizer from eliminating the copy
            _ = dest[0]
        }

        return totalGBs / Double(iterations)
    }
}

// MARK: - Prime Counting (CPU workload)

/// Simple sieve for reproducible CPU benchmark.
private func countPrimes(upTo limit: Int) -> Int {
    guard limit >= 2 else { return 0 }
    var sieve = [Bool](repeating: true, count: limit + 1)
    sieve[0] = false
    sieve[1] = false
    var i = 2
    while i * i <= limit {
        if sieve[i] {
            var j = i * i
            while j <= limit {
                sieve[j] = false
                j += i
            }
        }
        i += 1
    }
    return sieve.filter { $0 }.count
}
