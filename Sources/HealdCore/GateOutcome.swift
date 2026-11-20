/// What `SelfHealOrchestrator.fire` did with one action request.
public enum GateOutcome: Sendable, Equatable {
    case ran, cooldown, advisorDeferred, advisorSkipped, blockedAsk, blockedLog
}

/// Fate of queued scanner remediations (`app_restart`, `dns_flush`) after the fire gate.
public enum ScannerQueue {
    public enum Disposition: Sendable, Equatable {
        /// The action ran and drained the queue itself.
        case consumed
        /// Retry later: cooldown, advisor defer, or waiting for `heald approve` (consent=ask).
        case keep
        /// consent=log or advisor skip: never executed, discard.
        case drop
    }

    /// Under consent=ask the queue is kept; re-prompt at most this often (not every 60 s cooldown).
    public static let askRetryInterval: Double = 15 * 60

    public static func disposition(after outcome: GateOutcome) -> Disposition {
        switch outcome {
        case .ran: .consumed
        case .cooldown, .advisorDeferred, .blockedAsk: .keep
        case .blockedLog, .advisorSkipped: .drop
        }
    }
}
