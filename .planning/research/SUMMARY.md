# Project Research Summary

**Project:** macOS Guardian
**Domain:** macOS system monitoring daemon with self-healing capabilities and local web dashboard
**Researched:** 2026-03-03
**Confidence:** MEDIUM-HIGH

## Executive Summary

macOS Guardian is a self-healing system monitoring daemon — a fundamentally different category from passive monitors like iStat Menus or on-demand cleanup tools like CleanMyMac. The key insight from research is that no existing macOS tool closes the gap between detection and automated remediation: every competitor requires the user to notice a problem and manually trigger a fix. This project's value proposition is autonomous intervention — kill hung processes, restart crashed critical apps, detect orphaned LaunchAgents, flush broken DNS — all logged to a local web dashboard with a full audit trail.

The recommended implementation is a single Swift 6 daemon process running as a LaunchAgent (user context, not root), with an embedded Hummingbird 2 HTTP server for the dashboard, GRDB-backed SQLite for metric history and activity log, and native macOS APIs (sysctl, Mach host statistics, IOKit, proc_info) for system data collection. This stack avoids every major wrong turn: no Python runtime fragility, no Go's absent IOKit bindings, no Vapor's bloat, no Core Data in a headless process. The architecture is a clean Collector → Analyzer → Healer pipeline connected by in-process async channels, with the HTTP server as a read-only subscriber to the event bus.

The dominant risk in this project is the auto-healing logic itself: a kill rule with no process allowlist and no sustained-threshold requirement will eventually kill `kernel_task`, `WindowServer`, or `loginwindow`, dropping the user's session and losing unsaved work. This is not a hypothetical — it is the most common catastrophic failure mode for monitoring daemons. The second major risk is scope creep toward actions that SIP blocks entirely (disk permissions repair, writing to `/System`). Both risks are mitigated by architecture decisions made early: allowlist enforcement before any kill logic is wired up, and explicit SIP boundary mapping before any repair feature is planned.

## Key Findings

### Recommended Stack

The stack is fully native Swift 6, using only Apple-endorsed approaches for a macOS user-space daemon. Swift 6 concurrency (actors, async/await, structured task groups) is the correct mental model for the polling daemon loop — replacing legacy DispatchSourceTimer or Timer patterns that are unsupported in Swift 6 strict concurrency. The embedded Hummingbird 2 web server (not Vapor) is the right fit: minimal transitive dependencies, Swift 6 ready, and zero wasted weight for a single-machine localhost dashboard. OSLog replaces all file-based logging; it is native, searchable in Console.app, and requires no rotation logic. The target platform is macOS Sequoia (Darwin 25.4.0), so all modern APIs are available without compatibility constraints — but note that `periodic` has been removed in Sequoia and all scheduling must go through launchd.

**Core technologies:**
- Swift 6.x: Daemon language — only language with native IOKit/sysctl/Mach API access without bridging overhead; Swift 6 concurrency maps directly to polling daemon architecture
- Hummingbird 2.20.1: Local web server — lightweight, Swift 6 ready, no Foundation dependency, far leaner than Vapor for a localhost-only dashboard
- GRDB.swift 7.10.0: SQLite persistence — type-safe, Swift 6 concurrency-safe, zero-config single-file database; ideal for the write-heavy activity log and metric ring buffer
- swift-service-lifecycle 2.10.1: Daemon lifecycle orchestration — handles SIGTERM from launchd gracefully; Hummingbird already depends on it (zero extra cost)
- OSLog (system framework): Structured logging — native unified logging, no file management, searchable by subsystem/category in Console.app and `log` CLI
- sysctl / host_statistics64 / proc_pidinfo / IOKit: System monitoring APIs — no package install, accessed via Darwin module; these are the correct kernel interfaces for CPU, RAM, disk, and process data

**Do not use:** beltex/SystemKit (Swift 3, unmaintained), Python/psutil (runtime instability, no IOKit), Vapor (30+ transitive deps, wrong scope), Core Data (AppKit-tied, wrong for headless daemon), DispatchSourceTimer or Timer-based concurrency (incompatible with Swift 6 strict concurrency).

### Expected Features

The competitive gap is clear: macOS Guardian is the only tool that combines always-on daemon operation, automated remediation, and a persistent audit trail. Every existing tool (iStat Menus, CleanMyMac, OnyX, htop) is either passive or requires manual intervention.

**Must have (table stakes):**
- CPU + RAM + Disk monitoring (overall + per-volume) — baseline expectation for any system monitor
- Process list with top resource consumers — required for kill decisions and user trust
- LaunchAgent persistence (survives reboot, starts at login) — without this, nothing else matters
- Structured activity log (timestamped, queryable) — audit trail that makes autonomous action trustworthy
- Auto-kill hung processes (sustained high CPU, not on safelist) — the primary self-healing value proposition
- Basic web dashboard (localhost) — live metrics + activity feed; validates the "see what happened" use case
- Graceful SIGTERM handling — daemon must not corrupt state on launchd-initiated shutdown

**Should have (competitive differentiators):**
- Crash detection + auto-restart for user-defined critical apps — extends self-healing to app stability
- Orphaned LaunchAgent detection (plists whose binary no longer exists) — no competitor does this automatically
- Broken plist validation (`plutil -lint`) — proactive, no competitor does this
- DNS health check + auto-flush — common pain point, automated fix is the differentiator
- Swap spike detection with process context — improves diagnostic quality beyond simple alerting
- Configurable thresholds and watch list (TOML config, hot-reload) — power user unlock

**Defer (v2+):**
- Homebrew outdated package tracking — informational value, not self-healing; risky if auto-upgrade enabled
- S.M.A.R.T. disk health monitoring — requires deep IOKit dive or external tooling
- Cache and temp file cleanup on schedule — too risky without careful per-application safe-delete lists
- Historical charts beyond the activity feed — implementation complexity, not MVP
- macOS software update notification — low value relative to complexity

**Anti-features to avoid explicitly:**
- Aggressive memory compression forcing — wastes CPU, macOS manages this automatically
- Unattended `brew upgrade` — silently breaks developer toolchains, documented failure mode
- Automatic `fsck` / disk repair on critically failing disk — risks data corruption
- Kill any process over CPU threshold without sustained check and allowlist — catastrophic failure mode

### Architecture Approach

The architecture is a single daemon process with four clearly separated internal components connected by async channels: a Collector (polling loop, produces MetricSnapshot every 5 seconds), an Analyzer (stateless rules engine, emits Violations), a Healer (executes remediation actions, logs results), and an HTTP Server (serves dashboard HTML/JS and broadcasts metric snapshots via SSE). All components share a single event bus — no IPC, no XPC, no helper processes. Storage is SQLite (GRDB, WAL mode) for the metric ring buffer and a parallel NDJSON activity log for human-readable audit trail. The daemon runs as a LaunchAgent (user context), not a LaunchDaemon (root), because all remediation targets are user-owned processes and GUI automation requires user session context.

**Major components:**
1. LaunchAgent plist — starts daemon at login via launchd, `KeepAlive: true` provides self-healing for the daemon itself, `ThrottleInterval: 10` prevents crash loops
2. Collector — polls sysctl/Mach/IOKit every 5 seconds, produces immutable MetricSnapshot structs; isolated from all other logic, no side effects
3. Analyzer (Rules Engine) — pure stateless functions: snapshot in, Violations out; state (sustained threshold tracking) maintained in the Analyzer, not in rules; trivially testable
4. Healer — all shell-outs live here (`kill`, `launchctl kickstart`, `open -a`, `diskutil`, `brew`); allowlist checked before every action; backoff logic prevents repeated kills of same PID
5. Event Bus — in-process async channels fan out MetricSnapshot to SSE Hub, SQLite store, and Analyzer pipeline; decouples components without IPC
6. Embedded HTTP Server (Hummingbird) — listens on `127.0.0.1` only; serves static dashboard HTML/JS/CSS; REST endpoints for historical data; SSE endpoint for live push; never calls Collector directly
7. Storage (GRDB SQLite + NDJSON log) — WAL mode for concurrent reads; ring buffer for metrics (configurable retention, e.g. 24h); append-only NDJSON for activity events (grep-able, survives daemon restarts)

**Key patterns:**
- SSE (not WebSockets) for dashboard push — data flows server-to-browser only; SSE is simpler, auto-reconnects, no library required in browser
- Polling (not event-driven) for CPU/RAM/disk metrics — sampled counters need fixed intervals, not event hooks; 5s is the correct granularity
- LaunchAgent (not LaunchDaemon) — user context required for GUI app restart (`open -a`), Homebrew (refuses root), and AppleScript automation
- Rules as pure functions — stateless, testable, configurable, cannot corrupt state if they panic

### Critical Pitfalls

1. **Killing critical system processes** — A kill rule without an allowlist will eventually hit `kernel_task`, `WindowServer`, or `loginwindow`, dropping the user's session. Prevention: implement the allowlist and sustained-threshold check (5+ consecutive samples at threshold) before any auto-kill capability is wired up. The allowlist must cover all system UIDs and known system processes by name. Test explicitly against `kernel_task`.

2. **SIP-blocked repair actions silently failing** — Writes to `/System`, `/usr` (excluding `/usr/local`), `/bin`, `/sbin` fail silently even as root. `diskutil permissionsRepair` was removed in El Capitan. Planning any repair to these paths produces a feature that appears to work but does nothing. Prevention: map every planned repair action against the SIP boundary during architecture phase; remove any action that cannot succeed.

3. **TCC permission failures blocking daemon operation** — TCC grants are scoped to the specific executable binary. Granting Full Disk Access to Terminal does not grant it to the daemon binary. In macOS Sequoia, local network TCC can also affect dashboard accessibility. Prevention: installation procedure must include a `guardian doctor` command that verifies all required TCC permissions are granted to the daemon binary specifically.

4. **Daemon consumes more resources than it saves** — Process enumeration at 1-5 second intervals across all running processes is measurably expensive. A daemon that fixes 1% CPU from a misbehaving process while consuming 5% CPU is net-negative. Prevention: tiered polling intervals (5s for critical live metrics, 30-60s for process health checks, 5+ minutes for Homebrew/DNS); launchd `ProcessType: Background`; target budget of < 0.5% CPU average and < 50MB RAM.

5. **LaunchAgent not loading after reboot** — Plist validation passes but daemon silently fails to start after cold reboot due to path issues, permission problems ("Dubious ownership"), or boot timing. Prevention: test with a full cold reboot (not just `launchctl load`); set `ThrottleInterval` to prevent crash loops; configure `StandardOutPath`/`StandardErrorPath`; validate plist ownership (`root:wheel` for LaunchDaemon, user-owned for LaunchAgent).

6. **Homebrew auto-upgrade silently breaking developer toolchains** — `brew upgrade` without a package argument cascades through all dependencies, silently upgrading Python, OpenSSL, and other pinned toolchain components. Prevention: Homebrew actions must default to report-only (`brew outdated --quiet`); auto-upgrade is opt-in per-package, never default.

7. **Aggressive cleanup deleting non-garbage data** — Files in `~/Library/Caches/` and `/tmp/` include active browser caches, in-progress downloads, and application state. Age-based deletion heuristics cannot distinguish these from actual garbage. Prevention: any delete action must move to Trash (not `rm`), require explicit user confirmation, and be logged with full path and size before execution.

## Implications for Roadmap

Based on research, the architecture's own build-order section maps directly to a 7-phase structure. The critical dependency: Storage must exist before the Healer; HTTP Server must be wired to the event bus before auto-healing is enabled (so every action is immediately visible in the dashboard). The allowlist and sustained-threshold logic must be in place before any kill capability ships.

### Phase 1: Project Skeleton and LaunchAgent Setup

**Rationale:** Everything else depends on the daemon process running persistently. LaunchAgent is the foundation — without it, all other components have nowhere to live. This phase also forces early confrontation with TCC permission requirements and plist reliability, so these are understood before any feature work begins.
**Delivers:** A daemon binary that starts at login, survives restarts, handles SIGTERM gracefully, logs to OSLog, and can be installed/uninstalled cleanly. A `guardian doctor` command verifying required TCC permissions.
**Addresses:** LaunchAgent persistence (table stakes), graceful termination (table stakes)
**Avoids:** LaunchAgent not loading after reboot (Pitfall 7), TCC permission failures (Pitfall 3)
**Research flag:** Standard patterns — launchd is well-documented; skip deep research, use pitfalls checklist directly

### Phase 2: Metric Collector (Core Observability)

**Rationale:** The Collector is the data source for all downstream components. It must exist and be proven correct before storage, rules, or UI can be built on top of it. This phase also establishes the resource consumption baseline for the daemon — the budget must be set before features are added.
**Delivers:** CPU, RAM, disk, and process data collected at correct intervals (5s for metrics, 30-60s for process list). MetricSnapshot struct defined. Daemon resource consumption measured and budgeted at < 0.5% CPU / < 50MB RAM.
**Uses:** sysctl, host_statistics64, mach_host_statistics, proc_pidinfo, IOKit (via Darwin module); swift-argument-parser for CLI management
**Addresses:** CPU/RAM/disk monitoring (table stakes), process list with top consumers (table stakes)
**Avoids:** Daemon consuming more resources than it saves (Pitfall 4) — tiered polling intervals established here
**Research flag:** Standard patterns — Apple docs for sysctl/Mach APIs are authoritative; copy IOKit patterns from exelban/stats (MIT licensed)

### Phase 3: Storage Layer (SQLite Ring Buffer + Activity Log)

**Rationale:** Storage is the gateway dependency. The dashboard activity feed, the audit trail, and all historical queries require a persistent, queryable log. The Healer must not be built before this — auto-healing without a persistent log is a black box.
**Delivers:** GRDB SQLite database in WAL mode with metric ring buffer (configurable retention). Append-only NDJSON activity log. Both survive daemon restarts. Log rotation preventing unbounded disk growth.
**Uses:** GRDB.swift 7.10.0, SQLite WAL mode
**Addresses:** Structured activity log (table stakes), self-healing audit trail (differentiator)
**Avoids:** Writing logs to console output only (architecture anti-pattern), unbounded log growth (technical debt)
**Research flag:** Standard patterns — GRDB documentation is comprehensive; WAL mode concurrent read/write is a well-understood pattern

### Phase 4: Web Dashboard (HTTP Server + Live Metrics View)

**Rationale:** The dashboard makes the daemon's output visible to the user before any autonomous actions are taken. Building it here (before the Healer) ensures the user can verify the daemon is working correctly and that all future healing actions will be immediately visible in the UI.
**Delivers:** Hummingbird HTTP server embedded in daemon, listening on 127.0.0.1 only. Static dashboard HTML/CSS/JS served from binary resources. REST endpoints for historical metrics and events. SSE endpoint for live metric push. Dashboard shows live CPU/RAM/disk/process data and activity feed.
**Uses:** Hummingbird 2.20.1, HummingbirdWebSocket (if WebSocket chosen over SSE), swift-service-lifecycle
**Addresses:** Web dashboard live metrics (P1), activity feed UI (P1)
**Avoids:** XPC for web dashboard communication (architecture anti-pattern), web server running as root (security pitfall)
**Research flag:** Standard patterns for SSE and static file serving; Hummingbird v2 docs are good

### Phase 5: Rules Engine and Healer (Self-Healing Core)

**Rationale:** This is the project's primary value proposition and its highest risk phase. It must be built after storage (every action logged) and after the dashboard (every action visible). The allowlist and sustained-threshold check must be implemented and tested before the phase is considered complete.
**Delivers:** Stateless rules engine evaluating MetricSnapshots against configurable thresholds. Healer dispatching remediation actions with allowlist enforcement, sustained-threshold requirement (5+ consecutive samples), and exponential backoff on repeated kills of same PID. Every action logged to activity log and visible in dashboard immediately.
**Addresses:** Auto-kill hung processes (P1), self-healing audit trail with before/after state (differentiator)
**Avoids:** Killing critical system processes (Pitfall 1 — most critical), aggressive thresholds causing kill loops (UX pitfall)
**Research flag:** NEEDS DEEPER RESEARCH — allowlist completeness, sustained-threshold state machine design, and SIGTERM/SIGKILL sequence for non-launchd vs launchd-managed processes are all nuanced; run `gsd:research-phase` on this phase

### Phase 6: Extended Health Checks

**Rationale:** These features (orphaned LaunchAgent detection, DNS health check, broken plist validation, crash detection/auto-restart) are the differentiators that separate v1.x from MVP. They are independent of each other and of the core monitoring pipeline — each can be added incrementally without destabilizing what's already working.
**Delivers:** Orphaned LaunchAgent scanner (plists whose `ProgramArguments[0]` binary no longer exists). `plutil -lint` validation on all user-space plists. DNS probe with auto-flush on failure. Crash detection (PID existence check) with auto-restart for user-defined watch list apps via `open -a` or `launchctl kickstart`.
**Addresses:** Crash detection + auto-restart (P2), orphaned LaunchAgent detection (P2), broken plist validation (P2), DNS health check + auto-flush (P2)
**Avoids:** Using `launchctl` for restart of non-launchd-managed apps (architecture anti-pattern), running `brew upgrade` unattended (Pitfall 6)
**Research flag:** DNS flush requires `dscacheutil` + `killall mDNSResponder` — verify sudo requirements; crash detection watch list design may need research

### Phase 7: Configuration and Polish

**Rationale:** Power user configurability (TOML config file with hot-reload), swap spike detection with process context, and installation hardening should come last — after the core is proven stable and the feature set is validated.
**Delivers:** TOML config file for thresholds, watch list, and per-process allowlist overrides. Hot-reload on config file change. Swap spike detection correlating `vm_stat` deltas with top-RAM processes. Install script with file permission hardening (`root:wheel` on binary, correct plist ownership). Cold reboot acceptance test documented.
**Addresses:** Configurable thresholds and watch list (P2), swap spike detection (P2)
**Avoids:** LaunchDaemon security / privilege escalation via insecure file permissions (Pitfall 5), LaunchAgent not loading after reboot (Pitfall 7)
**Research flag:** Standard patterns — TOML config with FileWatch/FSEvents is well-understood; install script hardening follows documented launchd requirements

### Phase Ordering Rationale

- The Collector must precede Storage and Rules — you cannot store or analyze data you don't have
- Storage must precede the Healer — autonomous actions without a persistent audit trail are untraceable and untrustworthy
- The Dashboard must precede the Healer — the user must be able to verify all automated actions are visible before any automated actions fire
- The allowlist and sustained-threshold logic are gates on Phase 5, not phase-end polish — they ship at the start of the phase, not the end
- Extended health checks (Phase 6) are independent of each other and can be parallelized once the core pipeline exists
- Configuration and polish (Phase 7) last — premature generalization before the core is stable produces unused flexibility

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 5 (Rules Engine and Healer):** Process allowlist completeness (macOS Sequoia-specific process names), sustained-threshold state machine design, SIGTERM/SIGKILL sequencing for launchd-managed vs non-managed processes, backoff strategy for repeated violations. This is the highest-risk phase; run `gsd:research-phase` before implementation.
- **Phase 6 (Extended Health Checks):** DNS flush command sudo requirements in user-context LaunchAgent, crash detection watch list design for GUI vs CLI vs launchd-managed apps. Moderate research needed.

Phases with standard patterns (skip research-phase):
- **Phase 1 (LaunchAgent Setup):** launchd plist format and lifecycle are well-documented; pitfalls checklist is sufficient
- **Phase 2 (Collector):** sysctl/Mach API patterns documented in Apple developer docs; IOKit patterns available from exelban/stats MIT source
- **Phase 3 (Storage):** GRDB documentation is comprehensive; WAL mode concurrency is a standard pattern
- **Phase 4 (Dashboard):** Hummingbird 2 + SSE is well-documented; no novel integration challenges
- **Phase 7 (Polish):** TOML config and install hardening follow documented patterns

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Core technologies sourced from Apple official docs and verified package releases (Feb 2026). Swift 6 + Hummingbird 2 + GRDB 7 versions confirmed current. IOKit and sysctl patterns from Apple docs and MIT-licensed reference implementations. |
| Features | MEDIUM | Competitive analysis from official product pages (iStat Menus, CleanMyMac) and GitHub. Anti-feature rationale from community sources and domain reasoning. Feature prioritization matrix is a synthesis — individual priorities are defensible but not empirically validated. |
| Architecture | MEDIUM-HIGH | Core patterns (LaunchAgent, polling collector, SSE, event bus) from Apple official docs and verified open-source implementations. Build order derived from data flow dependencies, which are unambiguous. SSE vs WebSocket recommendation is well-supported. |
| Pitfalls | HIGH | SIP, TCC, and launchd pitfalls sourced from Apple official documentation and security research. Process allowlist pitfall is documented in multiple independent sources. Homebrew auto-upgrade risk is documented with specific real-world failure modes. |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Process allowlist completeness:** The allowlist in PITFALLS.md covers the most critical processes, but macOS Sequoia may have renamed or added system processes not covered. Validate against `ps aux` output sorted by UID on the target machine during Phase 5 research.
- **TCC local network scope in Sequoia:** PITFALLS.md notes that macOS Sequoia 15 introduced local network TCC. Research confirmed this applies to apps, not system daemons/root processes, but the exact behavior for a user-context LaunchAgent serving localhost HTTP is not definitively confirmed. Verify with a test binary during Phase 4 implementation.
- **Hummingbird 2 static file serving from binary resources:** The dashboard HTML/JS/CSS needs to be embedded in the binary or served from a known path. STACK.md does not detail the exact Hummingbird pattern for embedded static files — research during Phase 4.
- **Swap spike detection implementation:** The feature is called out in FEATURES.md but the exact `vm_stat` delta calculation approach is not detailed in any research file. Research during Phase 7 or when prioritized.

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: OSLog, IOKit, sysctl, host_statistics — official API references
- Apple Swift.org: Swift 6.2 release, swift-system-metrics 1.0 announcement (Feb 2026)
- Apple Support: System Integrity Protection (SIP) documentation
- launchd.info: Comprehensive launchd reference
- apple/swift-argument-parser GitHub (v1.7.0) — Apple-maintained
- groue/GRDB.swift GitHub (v7.10.0) — Full Swift 6 concurrency safety confirmed
- Microsoft Security Blog: CVE-2024-44243 SIP bypass — confirms SIP boundary behavior

### Secondary (MEDIUM confidence)
- hummingbird-project/hummingbird GitHub (v2.20.1) — active project, v2 released 2024
- swift-server/swift-service-lifecycle GitHub (v2.10.1)
- exelban/stats GitHub — open source macOS monitor, IOKit/SMC reference patterns (MIT)
- Red Canary Mac Monitor wiki — macOS system architecture (security-focused, accurate on kernel interfaces)
- Apple Developer Forums — CPU usage by process, XPC vs socket IPC
- SentinelOne blog — macOS Sequoia security changes, TCC bypass research
- bradleyjkemp.dev — LaunchDaemon hijacking via insecure permissions
- Heise Online — macOS 15 removes `periodic`
- macpaw.com — Why disk permissions repair is deprecated

### Tertiary (LOW confidence)
- Community blogs on Homebrew environment breakage — consistent with domain knowledge but secondary sources
- macOS cleanup community scripts — illustrative patterns only, not authoritative
- OnyX Wikipedia and community docs — feature comparison only

---
*Research completed: 2026-03-03*
*Ready for roadmap: yes*
