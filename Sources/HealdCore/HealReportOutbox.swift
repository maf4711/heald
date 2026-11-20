import Foundation

/// Durable outbox for heal reports: `heal_reports.ndjson` + byte-offset cursor `heal_report_cursor`
/// (same pattern as CloudPusher's activity cursor). The cursor only advances after a successful send.
public actor HealReportOutbox {
    public static let maxBatch = 100
    public static let defaultMaxBytes = 10 * 1024 * 1024
    public static let defaultSendTimeout: Duration = .seconds(8)
    /// Bytes of the outbox tail read at start-up to seed the collapse limiter.
    static let seedTailBytes = 512 * 1024
    /// Upper bound of one read; 100 reports × ≤ ~15 KB fit comfortably.
    static let readChunk = 4 * 1024 * 1024

    public struct Batch: Sendable {
        public var reports: [HealReport]
        public var nextOffset: UInt64
        public var corrupt: Int
    }

    public let fileURL: URL
    public let cursorURL: URL
    private let maxBytes: Int
    private let sendTimeout: Duration
    private var limiter = HealReportLimiter()
    /// Bytes removed from the head by rotation (monotonic; lets an in-flight flush rebase its offset).
    private var rotatedBytes: UInt64 = 0
    /// Corrupt lines skipped by committed flushes.
    public private(set) var corruptCount = 0
    /// Unsent reports dropped by rotation.
    public private(set) var droppedUnsent = 0
    /// Reports skipped as a poison batch (`skip(limit:)`).
    public private(set) var skippedCount = 0

    public init(directory: URL, maxBytes: Int = defaultMaxBytes, sendTimeout: Duration = defaultSendTimeout) {
        fileURL = directory.appendingPathComponent("heal_reports.ndjson")
        cursorURL = directory.appendingPathComponent("heal_report_cursor")
        self.maxBytes = maxBytes
        self.sendTimeout = sendTimeout
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        limiter = Self.seededLimiter(from: fileURL)
    }

    /// Restarts / crash loops must not multiply collapsed reports: seed from what is already queued.
    private static func seededLimiter(from url: URL) -> HealReportLimiter {
        var limiter = HealReportLimiter()
        guard let h = try? FileHandle(forReadingFrom: url) else { return limiter }
        defer { try? h.close() }
        let end = (try? h.seekToEnd()) ?? 0
        let start = end > UInt64(seedTailBytes) ? end - UInt64(seedTailBytes) : 0
        guard (try? h.seek(toOffset: start)) != nil, let data = try? h.readToEnd() else { return limiter }
        let decoder = DiagnosisEngine.decoder()
        for line in data.split(separator: 0x0A) {
            if let r = try? decoder.decode(HealReport.self, from: line) { limiter.seed(r) }
        }
        return limiter
    }

    // MARK: append

    /// Append one report as a single `write(2)` with O_APPEND (intact lines even with several writers).
    /// Returns false when the report was collapsed (`HealReportLimiter`) or could not be written.
    @discardableResult
    public func append(_ report: HealReport) -> Bool {
        var report = report
        guard limiter.admit(&report) else { return false }
        guard var line = try? DiagnosisEngine.encoder().encode(report) else { return false }
        line.append(0x0A)
        let fd = open(fileURL.path, O_RDWR | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // A crash mid-write can leave a half line: terminate it so this report starts on its own line.
        var st = stat()
        var lastByte: UInt8 = 0x0A
        if fstat(fd, &st) == 0, st.st_size > 0, pread(fd, &lastByte, 1, st.st_size - 1) == 1, lastByte != 0x0A {
            line.insert(0x0A, at: line.startIndex)
        }
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { return false }
        if fstat(fd, &st) == 0, st.st_size > maxBytes { rotate() }
        return true
    }

    /// Keep the newest lines (≤ 3/4 of the cap, line-aligned); shift the cursor by the bytes dropped.
    /// Assumes a single-writer process (the daemon): the rewrite + rename is not coordinated with
    /// other processes appending concurrently (their line could land in the replaced file).
    private func rotate() {
        guard let data = try? Data(contentsOf: fileURL), data.count > maxBytes else { return }
        var start = data.count - maxBytes * 3 / 4
        while start < data.count, data[start - 1] != 0x0A { start += 1 }
        let dropped = UInt64(start)
        let cursor = loadCursor()
        if cursor < dropped {
            droppedUnsent += data[Int(cursor)..<start].reduce(0) { $0 + ($1 == 0x0A ? 1 : 0) }
        }
        let tmp = fileURL.appendingPathExtension("tmp-\(UUID().uuidString)")
        guard (try? data[start...].write(to: tmp)) != nil,
              rename(tmp.path, fileURL.path) == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            return
        }
        rotatedBytes += dropped
        saveCursor(cursor > dropped ? cursor - dropped : 0)
    }

    // MARK: read

    /// Up to `limit` reports after `offset`. Only newline-terminated lines are consumed;
    /// undecodable lines are skipped (counted in `corrupt`).
    public func readBatch(since offset: UInt64, limit: Int) -> Batch {
        var batch = Batch(reports: [], nextOffset: offset, corrupt: 0)
        guard limit > 0, let h = try? FileHandle(forReadingFrom: fileURL) else { return batch }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: offset)) != nil,
              let chunk = try? h.read(upToCount: Self.readChunk), !chunk.isEmpty else { return batch }
        let decoder = DiagnosisEngine.decoder()
        var lineStart = chunk.startIndex
        while batch.reports.count < limit,
              let nl = chunk[lineStart...].firstIndex(of: 0x0A) {
            let line = chunk[lineStart..<nl]
            if !line.isEmpty {
                if let r = try? decoder.decode(HealReport.self, from: line) {
                    batch.reports.append(r)
                } else {
                    batch.corrupt += 1
                }
            }
            lineStart = nl + 1
        }
        // A full chunk without any newline is one oversized garbage line: skip it.
        if lineStart == chunk.startIndex, chunk.count == Self.readChunk {
            batch.corrupt += 1
            lineStart = chunk.endIndex
        }
        batch.nextOffset = offset + UInt64(lineStart - chunk.startIndex)
        return batch
    }

    public func committedOffset() -> UInt64 { loadCursor() }

    /// Advance the cursor past the next batch without sending it (a poison batch the ingest
    /// rejected with 4xx while an empty push succeeded). Returns the number of reports skipped.
    @discardableResult
    public func skip(limit: Int = maxBatch) -> Int {
        let (cursor, batch) = pendingBatch(limit: limit)
        guard batch.nextOffset > cursor else { return 0 }
        saveCursor(batch.nextOffset)
        corruptCount += batch.corrupt
        skippedCount += batch.reports.count
        return batch.reports.count
    }

    // MARK: flush

    /// Read ≤ min(limit, 100) reports after the cursor and hand them to `send` (called exactly once,
    /// also with an empty batch so callers can piggy-back on their regular push). The cursor advances
    /// only when `send` returns true within the timeout; false / throw / timeout leave it unchanged.
    /// Returns the number of reports committed.
    @discardableResult
    public func flush(
        limit: Int = maxBatch,
        send: @escaping @Sendable ([HealReport]) async throws -> Bool
    ) async -> Int {
        let batch = pendingBatch(limit: limit).batch
        let rotatedBefore = rotatedBytes
        let reports = batch.reports
        let result = await AutohealAdvisor.withDeadline(sendTimeout) {
            (try? await send(reports)) ?? false
        }
        guard case .value(true) = result else { return 0 }
        let shift = rotatedBytes - rotatedBefore // rotation during the send moved the head
        saveCursor(batch.nextOffset > shift ? batch.nextOffset - shift : 0)
        corruptCount += batch.corrupt
        return reports.count
    }

    /// The committed cursor and the next ≤ min(limit, 100) reports after it.
    private func pendingBatch(limit: Int) -> (cursor: UInt64, batch: Batch) {
        var cursor = loadCursor()
        if cursor > fileSize() { cursor = 0 } // file replaced or truncated externally
        return (cursor, readBatch(since: cursor, limit: min(limit, Self.maxBatch)))
    }

    // MARK: files

    private func fileSize() -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }

    private func loadCursor() -> UInt64 {
        guard let raw = try? String(contentsOf: cursorURL, encoding: .utf8) else { return 0 }
        return UInt64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func saveCursor(_ offset: UInt64) {
        try? String(offset).write(to: cursorURL, atomically: true, encoding: .utf8)
    }
}
