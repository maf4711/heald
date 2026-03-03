# Phase 2: Metric Collector - Context

**Gathered:** 2026-03-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Continuously collect CPU, RAM, disk, and process data at correct polling intervals, within the daemon's resource budget (< 1% CPU, < 50MB RAM). This phase collects and exposes data internally — storage (Phase 3) and cloud push (Phase 4) consume it downstream. No kill logic, no notifications, no persistence to disk.

</domain>

<decisions>
## Implementation Decisions

### CPU metrics
- Track overall CPU usage AND per-core breakdown (MON-01 specifies "gesamt + pro Core")
- Polling interval: 5 seconds

### RAM metrics
- Track Used, Wired, Compressed, Swap as specified in MON-02
- Polling interval: 5 seconds

### Process snapshots
- Track top 25 processes by CPU and top 25 by RAM as two separate ranked lists
- Include all processes (system daemons and user-space) but tag system daemons with a `system` flag
- This flag feeds into Phase 5 safelist logic — system-tagged processes are never killed

### Claude's Discretion
- **Polling intervals for disk/S.M.A.R.T.**: Choose appropriate intervals based on how fast each metric changes. Disk space changes slowly; S.M.A.R.T. even slower. CPU/RAM at 5s is fixed.
- **Process metadata fields**: Pick fields that feed well into downstream phases (storage, dashboard, kill logic). PID + name + CPU% + RAM are minimum; consider parent PID, user, start time if useful.
- **Swap spike detection**: Choose detection strategy (absolute threshold, rate-of-change, or both) that catches real problems without false positives on normal macOS memory behavior.
- **Swap spike attribution**: Choose between delta tracking (comparing per-process memory between snapshots) or highest-RAM heuristic. Accuracy matters for Phase 5 kill decisions.
- **Memory pressure tracking**: Decide whether to include macOS memory pressure level (nominal/warn/critical) as a first-class metric alongside raw RAM numbers.
- **Spike severity signaling**: Decide how to signal swap spikes within Phase 2's scope (OSLog levels, etc.). Full notifications come in Phase 7.
- **Debug access**: Decide whether to expose current metrics via OSLog only, a JSON status file, or another pragmatic method before the cloud dashboard arrives in Phase 4.

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The user trusts the builder to make implementation decisions for this infrastructure phase.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `HealdService` (Sources/heald/HealdService.swift): Currently idle skeleton with graceful shutdown. Phase 2 replaces `Task.sleep(for: .seconds(Int.max))` with active collection loops.
- `Logger` extensions (Sources/heald/Logging.swift): Already has `.collector` and `.analyzer` categories planned as comments. Phase 2 activates `.collector`.

### Established Patterns
- Swift 6 strict concurrency — all new types must be Sendable
- ServiceLifecycle pattern — services run inside `ServiceGroup`, receive graceful shutdown signals
- OSLog with subsystem `com.heald.daemon` and category-based loggers
- macOS 15+ platform target — can use latest Darwin APIs

### Integration Points
- HealdService.run() — metric collection loops integrate here
- Package.swift — may need new dependencies for system metric APIs (or use Darwin/IOKit directly)
- Logging.swift — activate `.collector` category, potentially add `.metrics` or `.process`

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-metric-collector*
*Context gathered: 2026-03-03*
