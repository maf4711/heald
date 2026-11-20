import Testing
@testable import HealdCore

/// Reviewer F2/N8: queued scanner fixes vs the fire gate outcome.
struct ScannerQueueTests {
    @Test func queuedScannerRequestsSurviveDeferAndAskButNotLog() throws {
        #expect(ScannerQueue.disposition(after: .ran) == .consumed)
        #expect(ScannerQueue.disposition(after: .cooldown) == .keep)
        #expect(ScannerQueue.disposition(after: .advisorDeferred) == .keep)
        #expect(ScannerQueue.disposition(after: .blockedAsk) == .keep)
        #expect(ScannerQueue.disposition(after: .blockedLog) == .drop)
        #expect(ScannerQueue.disposition(after: .advisorSkipped) == .drop)
    }
}
