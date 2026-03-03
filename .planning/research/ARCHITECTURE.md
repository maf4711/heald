# Architecture Research

**Domain:** macOS system monitoring daemon with self-healing capabilities and local web dashboard
**Researched:** 2026-03-03
**Confidence:** MEDIUM-HIGH (core patterns from Apple official docs; implementation specifics from verified open-source projects and community sources)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                      USER LAYER                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Web Browser (localhost:PORT)                             │   │
│  │  - Live Dashboard (CPU/RAM/Disk/Processes)                │   │
│  │  - Activity Feed (events + actions taken)                 │   │
│  └──────────────────┬───────────────────────────────────────┘   │
└─────────────────────│───────────────────────────────────────────┘
                      │ HTTP / SSE (Server-Sent Events)
┌─────────────────────▼───────────────────────────────────────────┐
│                   DAEMON PROCESS                                  │
│  (LaunchAgent: ~/Library/LaunchAgents/com.user.guardian.plist)  │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                  Embedded HTTP Server                     │    │
│  │  - REST API for current metrics snapshot                  │    │
│  │  - SSE endpoint for live metric stream                    │    │
│  │  - Static file serving (dashboard HTML/JS/CSS)            │    │
│  └──────────────────┬──────────────────────────────────────┘    │
│                     │ internal function calls                     │
│  ┌──────────────────▼──────────────────────────────────────┐    │
│  │                  Core Engine                              │    │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐ │    │
│  │  │  Collector  │  │  Analyzer  │  │    Healer          │ │    │
│  │  │  (polling)  │  │ (rules     │  │ (actions on        │ │    │
│  │  │            │  │  engine)   │  │  violations)       │ │    │
│  │  └─────┬──────┘  └─────┬──────┘  └────────┬───────────┘ │    │
│  └────────│───────────────│──────────────────│─────────────┘    │
│           │               │                  │                   │
│           │ writes        │ reads+evaluates  │ executes          │
│  ┌────────▼───────────────▼──────────────────▼───────────────┐  │
│  │                   Event Bus (in-process)                    │  │
│  │       MetricSnapshot → RuleViolation → HealAction          │  │
│  └────────────────────────┬───────────────────────────────────┘  │
│                            │ persists                             │
│  ┌─────────────────────────▼──────────────────────────────────┐  │
│  │                    Storage Layer                             │  │
│  │  ┌──────────────────────┐  ┌────────────────────────────┐  │  │
│  │  │  SQLite DB           │  │  Structured Log File       │  │  │
│  │  │  (metrics ring buf.) │  │  (activity feed, NDJSON)   │  │  │
│  │  └──────────────────────┘  └────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                      │
           ┌──────────▼──────────┐
           │   macOS Kernel APIs  │
           │  sysctl / Mach host  │
           │  proc_info / IOKit   │
           │  launchctl / shell   │
           └─────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| **LaunchAgent plist** | Starts daemon at login, restarts on crash, sets env | `~/Library/LaunchAgents/com.user.guardian.plist` with `KeepAlive: true` |
| **Collector** | Polls system metrics on a fixed interval (e.g. every 5s) | Calls `sysctl`, Mach `host_statistics`, `proc_info`, `IOKit` |
| **Analyzer / Rules Engine** | Evaluates metric snapshots against threshold rules | Stateless rule functions: `if cpu > 90% for 30s → violation` |
| **Healer** | Executes remediation actions (kill, relaunch, diskutil) | Shell-outs to `kill`, `launchctl`, `diskutil`, `brew` with backoff |
| **Event Bus** | In-process channel from Collector → Analyzer → Healer → HTTP | Async channel / queue; decouples components without IPC overhead |
| **Embedded HTTP Server** | Serves dashboard HTML and metrics API | Hummingbird (Swift) or FastAPI (Python); listens on `127.0.0.1` only |
| **SSE Endpoint** | Pushes real-time metric stream to browser | `text/event-stream` chunked response; re-broadcasts Collector output |
| **SQLite DB** | Ring-buffer of recent metric snapshots for charts | `metrics(ts, cpu_pct, ram_mb, disk_free_gb, ...)` with rolling delete |
| **Activity Log** | Append-only record of detections and fixes | NDJSON file or SQLite table; source for dashboard activity feed |

## Recommended Project Structure

```
guardian/
├── cmd/
│   └── guardian/        # Entry point: parse args, wire components, start
├── collector/           # System metric collection
│   ├── cpu.go           # Mach host_statistics / sysctl
│   ├── memory.go        # vm_statistics64
│   ├── disk.go          # statfs / IOKit StorageKit
│   ├── processes.go     # proc_info / sysctl KERN_PROC
│   └── collector.go     # Ticker loop, aggregates → MetricSnapshot
├── rules/               # Threshold definitions and evaluation
│   ├── rules.go         # RuleSet, evaluate(snapshot) → []Violation
│   └── defaults.go      # Default thresholds (cpu 90%, ram 85%, etc.)
├── healer/              # Remediation action handlers
│   ├── healer.go        # Dispatch violation → action
│   ├── kill.go          # kill / SIGTERM with fallback to SIGKILL
│   ├── relaunch.go      # launchctl kickstart / open -a
│   └── system.go        # diskutil, brew upgrade, dns flush
├── store/               # Persistence
│   ├── db.go            # SQLite: metrics ring buffer
│   └── log.go           # NDJSON activity log writer/reader
├── web/                 # HTTP server + dashboard assets
│   ├── server.go        # Route registration, SSE hub
│   ├── api.go           # /api/metrics, /api/events REST handlers
│   ├── sse.go           # /api/stream SSE endpoint
│   └── static/          # dashboard.html, app.js, style.css
├── launchd/
│   └── com.user.guardian.plist  # LaunchAgent template
└── config.go            # Thresholds, ports, intervals — TOML or JSON
```

### Structure Rationale

- **collector/:** Isolated from all other logic. Can be unit-tested by mocking the syscall layer. Owns the polling loop and produces immutable `MetricSnapshot` structs.
- **rules/:** Pure functions with no side effects. A snapshot goes in, violations come out. Trivially testable and changeable without touching the healer.
- **healer/:** All shell-outs live here. Logging every action before and after it executes is mandatory. Backoff logic (don't kill the same PID twice in 30s) lives here.
- **store/:** Single writer from the event bus. SQLite is the right embedded store for structured time-series; the activity log is append-only NDJSON for simplicity and grep-ability.
- **web/:** Receives snapshots via a broadcast channel from the event bus. Never calls the collector directly — avoids coupling and double-polling.

## Architectural Patterns

### Pattern 1: LaunchAgent with KeepAlive (Self-Healing via launchd)

**What:** Register the daemon's own plist with `KeepAlive: true` in `~/Library/LaunchAgents/`. launchd watches the process and relaunches it if it exits, crashes, or is killed.

**When to use:** Always — this is the macOS-native mechanism for persistent background processes. It is free, requires no custom watchdog code, and survives user logout if needed.

**Trade-offs:** LaunchAgent (per-user, starts at login) is preferred over LaunchDaemon (root, starts at boot) because process killing of user-owned apps does not need root. LaunchDaemon requires root and cannot reach per-user session state.

**Example:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.guardian</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/guardian</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>/tmp/guardian.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/guardian.error.log</string>
</dict>
</plist>
```

### Pattern 2: Polling Collector with Fixed Interval (not event-driven)

**What:** A ticker fires every N seconds (5s for live dashboard, 60s for slower health checks). Each tick collects a full `MetricSnapshot` and puts it on the event bus.

**When to use:** For CPU, RAM, and disk metrics — these are sampled counters, not events. Event-driven APIs (IOKit notifications, Endpoint Security) are appropriate only for discrete system events (device plug/unplug, process exec), not for continuous resource metrics.

**Trade-offs:** Polling is slightly wasteful but predictable. The resource cost of a 5-second sysctl poll is negligible (microseconds). Event-driven approaches for metrics introduce complexity with minimal benefit for a local tool.

**Example:**
```go
func (c *Collector) Run(ctx context.Context, out chan<- MetricSnapshot) {
    ticker := time.NewTicker(5 * time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ticker.C:
            snap, err := c.collect()
            if err == nil {
                out <- snap
            }
        case <-ctx.Done():
            return
        }
    }
}
```

### Pattern 3: SSE for Real-Time Dashboard Push

**What:** The embedded HTTP server maintains an SSE hub. When a new `MetricSnapshot` arrives via the event bus, the hub broadcasts it as a JSON-encoded `data:` event to all connected browsers.

**When to use:** Always prefer SSE over WebSockets for a monitoring dashboard. Data flows server → browser only. SSE is simpler: standard HTTP, auto-reconnect built into browsers, no library required.

**Trade-offs:** SSE cannot receive data from the browser. This is fine — the dashboard is read-only. If a control plane (e.g. "kill this process now" button) is needed later, add a separate POST endpoint.

**Example:**
```go
// SSE hub broadcasts to all connected clients
type SSEHub struct {
    mu      sync.Mutex
    clients map[chan string]struct{}
}

func (h *SSEHub) Broadcast(data string) {
    h.mu.Lock()
    defer h.mu.Unlock()
    for ch := range h.clients {
        select {
        case ch <- data:
        default: // drop if slow client
        }
    }
}

// HTTP handler
func (h *SSEHub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "text/event-stream")
    w.Header().Set("Cache-Control", "no-cache")
    ch := make(chan string, 16)
    h.register(ch)
    defer h.unregister(ch)
    for {
        select {
        case msg := <-ch:
            fmt.Fprintf(w, "data: %s\n\n", msg)
            w.(http.Flusher).Flush()
        case <-r.Context().Done():
            return
        }
    }
}
```

### Pattern 4: Rules Engine as Pure Functions

**What:** Rules are stateless functions that take a `MetricSnapshot` and return zero or more `Violation` values. State (e.g. "CPU was high for the last 3 consecutive ticks") is maintained by the Analyzer, not the rules.

**When to use:** Always. Stateless rules are trivially testable, easily configurable via a config file, and cannot corrupt state if they panic.

**Trade-offs:** Time-based rules ("CPU > 90% for 30 seconds") require the Analyzer to track a sliding window per metric. This is a small amount of state but lives in one place.

## Data Flow

### Metric Collection Flow (every 5 seconds)

```
Kernel APIs (sysctl, host_statistics, proc_info)
    ↓ poll
Collector → MetricSnapshot{cpu, ram, disk, processes, ts}
    ↓ channel
Event Bus
    ├──→ Analyzer: evaluate rules → []Violation
    │        ↓ if violation
    │       Healer: execute action → ActionResult
    │        ↓
    │       Event Bus: emit ActivityEvent{type, target, action, ts}
    │
    ├──→ SSE Hub: broadcast snapshot as JSON to browser clients
    │
    └──→ Store: write snapshot to SQLite ring buffer
                write ActivityEvent to NDJSON log
```

### Dashboard Request Flow (on page load)

```
Browser GET /
    ↓
HTTP Server → serve static dashboard.html
Browser GET /api/metrics?last=300   (last 5 minutes)
    ↓
HTTP Server → Store.QueryMetrics(last300s) → JSON array → browser
Browser GET /api/events?last=100
    ↓
HTTP Server → Store.QueryEvents(last100) → JSON array → browser
Browser GET /api/stream            (SSE connection, stays open)
    ↓
SSE Hub → push each new MetricSnapshot as it arrives
```

### Key Data Structures

```go
type MetricSnapshot struct {
    Timestamp  time.Time
    CPU        CPUMetrics     // user%, sys%, idle% per core + total
    Memory     MemoryMetrics  // total, used, wired, compressed, swap
    Disk       []DiskMetrics  // per mount: total, free, read/write IOPS
    Processes  []ProcessInfo  // top 20 by CPU+RAM: pid, name, cpu%, rss
}

type Violation struct {
    Rule     string    // "cpu_sustained_high", "process_hung", etc.
    Target   string    // process name or metric name
    Value    float64   // observed value
    Severity string    // "warn", "critical"
}

type ActivityEvent struct {
    Timestamp time.Time
    Type      string    // "detection", "action", "error"
    Rule      string
    Target    string
    Action    string    // "killed", "restarted", "ignored"
    Result    string    // "success", "failed", "skipped"
}
```

## Build Order (Phase Dependencies)

The correct build sequence follows data flow dependencies — each layer must exist before the layer that consumes it:

```
Phase 1: Project skeleton + LaunchAgent plumbing
    ↓ (daemon can start/stop/restart)
Phase 2: Collector (metric APIs)
    ↓ (data exists to analyze)
Phase 3: Storage (SQLite + activity log)
    ↓ (history exists to serve)
Phase 4: Embedded HTTP server + static dashboard
    ↓ (UI can show current state)
Phase 5: Rules Engine + Healer (self-healing)
    ↓ (autonomous actions logged + visible)
Phase 6: System health checks (disk perms, Homebrew, DNS, plists)
    ↓ (all checks wired into same rules/healer pipeline)
Phase 7: Polish (config file, install script, thresholds UX)
```

**Critical dependency:** The HTTP server must be wired to the event bus before the rules engine. This ensures every action the healer takes is immediately visible in the dashboard activity feed.

**Do not build the healer before storage.** Without a persistent activity log, auto-healing is a black box and debugging why a process was killed is impossible.

## Scaling Considerations

This is a single-machine local tool. Scaling in the traditional sense does not apply. The relevant "scaling" concerns are resource usage constraints:

| Concern | Approach |
|---------|----------|
| Daemon's own CPU usage | Keep polling interval >= 5s; avoid busy loops; one goroutine per component |
| Daemon's own RAM usage | SQLite ring buffer with configurable retention (e.g. 24h); log rotation |
| Dashboard responsiveness | SSE with server-side throttle (don't push faster than 1s); lightweight HTML/JS with no heavy framework |
| Startup time | < 1s; launchd will kill daemons that exit too fast repeatedly (throttle interval) |
| SQLite concurrency | Single writer (the event bus consumer); multiple readers (HTTP handlers); use WAL mode |

## Anti-Patterns

### Anti-Pattern 1: Using LaunchDaemon Instead of LaunchAgent

**What people do:** Install the plist in `/Library/LaunchDaemons/` to get root privileges and boot-time start.

**Why it's wrong:** Root is not needed for monitoring user-owned processes. LaunchDaemon cannot access per-user GUI session, cannot restart GUI apps, and requires `sudo launchctl` for every install/uninstall. It also runs when no user is logged in, which is wasted work.

**Do this instead:** Use `~/Library/LaunchAgents/`. This runs as the user, can kill and restart any process the user owns, starts at login, and is self-contained in the user's home directory.

### Anti-Pattern 2: Polling Kernel APIs Faster than 1-Second Intervals

**What people do:** Poll CPU/RAM every 100-500ms for "smoother" dashboard graphs.

**Why it's wrong:** The CPU usage calculation via `host_statistics` requires two samples separated by a time delta to compute utilization. Polling faster than 1s produces noisy, misleading numbers. Also, the overhead of repeated syscalls at high frequency becomes measurable.

**Do this instead:** Poll every 5 seconds for metrics collection. The SSE stream can still update the dashboard on each snapshot. For charts, 5-second granularity is sufficient for trend analysis.

### Anti-Pattern 3: Calling `launchctl` for Process Restart Instead of Using Signal + Retry

**What people do:** Use `launchctl kickstart` or `launchctl stop/start` to restart arbitrary apps that are not launchd-managed.

**Why it's wrong:** Only processes loaded as launchd services can be managed with `launchctl`. Most user apps (e.g. Finder, Safari, a crashed utility) are NOT launchd jobs — they are launched by the user or by `NSWorkspace`. Using `launchctl` on non-managed processes will fail silently or with confusing errors.

**Do this instead:** For non-launchd apps: send SIGTERM, wait 3s, send SIGKILL if still running, then use `open -a "AppName"` or `NSWorkspace.launchApplication` to relaunch. For launchd-managed services: use `launchctl kickstart -k <domain>/<label>`.

### Anti-Pattern 4: XPC for Web Dashboard Communication

**What people do:** Use Apple XPC to communicate between the daemon and a separate dashboard helper process.

**Why it's wrong:** XPC is ideal for daemon-to-daemon IPC within macOS's security model, but it cannot talk to a web browser. A web dashboard requires an HTTP server regardless. Adding XPC on top adds a pointless extra hop: Daemon → XPC → Helper → HTTP.

**Do this instead:** Embed the HTTP server directly in the daemon process. The daemon is the single source of truth for metrics and serves them directly via HTTP to the browser. This eliminates the helper process entirely.

### Anti-Pattern 5: Writing Logs to Console Output Only

**What people do:** Use `print()` / `NSLog()` and rely on `Console.app` or the launchd standard output file for the activity log.

**Why it's wrong:** Console output is volatile — it disappears when the daemon restarts, cannot be queried, and requires a separate macOS tool to read. The dashboard activity feed needs structured, queryable history.

**Do this instead:** Write an append-only NDJSON log file AND store events in SQLite. The NDJSON file is human-readable and grep-able. SQLite supports the dashboard's paginated event queries. Both survive daemon restarts.

## Integration Points

### macOS System APIs

| API | Integration Pattern | Confidence | Notes |
|-----|---------------------|------------|-------|
| `sysctl KERN_PROC` | Direct syscall from daemon process | HIGH (Apple docs) | Lists all running processes with CPU/RSS |
| `host_statistics` (Mach) | `host_statistics64(mach_host_self(), HOST_VM_INFO64, ...)` | HIGH (Apple docs) | VM stats: wired, active, inactive, compressed |
| `host_cpu_load_info` | `host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ...)` | HIGH (Apple docs) | CPU ticks per state; must diff two samples |
| `statfs` / `getattrlist` | Standard POSIX syscall | HIGH | Disk free/used per mount point |
| `proc_info` | `proc_pidinfo()` from `<libproc.h>` | MEDIUM (documented, private-ish) | Per-process CPU time and memory |
| `IOKit` (SMC/sensors) | `IOServiceGetMatchingServices` | MEDIUM (not App Store safe) | Temperature, fan speed — skip unless needed |
| `launchctl` | Shell-out via `exec` | HIGH | Managing launchd services |
| `kill(pid, signal)` | POSIX signal; only works for user-owned PIDs | HIGH | No root = cannot kill system processes |
| `open -a` / `NSWorkspace` | Shell-out or framework call | HIGH | Relaunching GUI apps |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Collector → Analyzer | Buffered channel (N=10) | Drop oldest if analyzer is slow; never block collector |
| Analyzer → Healer | Buffered channel (N=5) | Violations; healer may be slow (waits for process to die) |
| Collector → SSE Hub | Broadcast channel (fan-out) | One snapshot → all connected clients |
| Collector → Store | Direct function call (sync write) | SQLite WAL mode allows concurrent reads |
| Healer → Store | Direct function call (sync write) | ActivityEvent written immediately after action |
| HTTP Handlers → Store | Direct function call (read-only) | Multiple concurrent readers safe in WAL mode |

## Sources

- Apple Developer Documentation: Creating Launch Daemons and Agents — https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html (MEDIUM: archive docs, verified patterns still current)
- Apple Developer Documentation: Designing Daemons and Services — https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html
- Apple Developer Forums: Obtaining CPU usage by process — https://developer.apple.com/forums/thread/655349 (MEDIUM)
- Red Canary Mac Monitor: macOS System Architecture — https://github.com/redcanaryco/mac-monitor/wiki/3.-macOS-System-Architecture (MEDIUM: security-focused but accurate on kernel interfaces)
- swift-system-metrics (Apple) — https://github.com/apple/swift-system-metrics (HIGH: official Apple Swift package)
- Hummingbird Swift HTTP framework — https://github.com/hummingbird-project/hummingbird (MEDIUM: active project, 2024 v2 release)
- Victor on Software: macOS launchd agents and daemons — https://victoronsoftware.com/posts/macos-launchd-agents-and-daemons/ (LOW: third-party blog, consistent with Apple docs)
- launchd.info tutorial — https://launchd.info/ (MEDIUM: well-maintained community reference)
- Apple Developer Forums: XPC vs socket-based IPC — https://developer.apple.com/forums/thread/74498 (MEDIUM)
- SQLite best practices for time series — https://moldstud.com/articles/p-handling-time-series-data-in-sqlite-best-practices (LOW: community article)
- exelban/stats open source macOS monitor — https://github.com/exelban/stats (MEDIUM: reference implementation showing real-world approach)

---
*Architecture research for: macOS self-healing system monitoring daemon with web dashboard*
*Researched: 2026-03-03*
