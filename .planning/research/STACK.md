# Stack Research

**Domain:** macOS system monitoring daemon with auto-repair and local web dashboard
**Researched:** 2026-03-03
**Confidence:** MEDIUM-HIGH (core stack HIGH, some peripheral choices MEDIUM)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Swift | 6.x (via Swift 6.2 toolchain) | Daemon language | Native macOS APIs (IOKit, sysctl, Mach, OSLog) require Swift or ObjC. First-class access to Apple system frameworks without bridging overhead. Swift 6 concurrency (actors, async/await) maps perfectly to the polling daemon loop pattern. Go and Python are ruled out — Go has no native IOKit/SMC bindings, Python has too much startup overhead for a lean daemon. |
| Hummingbird 2 | 2.20.1 | Local web server for dashboard | Minimal deps (only SwiftNIO), no Foundation dependency, Swift 6 ready, far lighter than Vapor for a single-machine localhost server. Vapor's full-stack weight is wasted here — dashboard only needs an HTTP server + websockets + static file serving. Hummingbird's modular design lets us add only what's needed. |
| SQLite (via GRDB.swift) | GRDB 7.10.0 | Persist activity log, health snapshots | Zero-config, single-file database on local disk. No network, no service, restarts cleanly with the daemon. GRDB is type-safe, Swift 6 ready, and spares enormous ORM boilerplate vs raw SQLite C API. Event log is write-heavy but read-light — perfect SQLite fit. |
| swift-service-lifecycle | 2.10.1 | Daemon startup/shutdown orchestration | Provides graceful signal handling (SIGTERM from launchd) and structured concurrency-aware lifecycle management. Prevents resource leaks on shutdown. Hummingbird already depends on this, so it's zero extra cost. |
| OSLog (system framework) | Bundled with macOS | Structured log output to Console.app | Apple's native unified logging. Zero extra dependency. Readable in Console.app and `log` CLI. Persisted automatically to /var/db/diagnostics. Do NOT use swift-log as the primary logging sink for a macOS daemon — OSLog is natively integrated, searchable by subsystem/category, and requires no file management. |

### System Monitoring APIs

These are macOS system APIs, not Swift packages. No package manager install needed.

| API | Purpose | How to Use |
|-----|---------|------------|
| `sysctl` / `host_statistics64` | CPU usage (user/system/idle), total RAM, active/wired/free memory | Call via Darwin module, wrap in Swift structs. Reference: beltex/SystemKit for patterns (unmaintained, copy the technique not the library) |
| `proc_listpids` + `proc_pidinfo` | Enumerate running processes, get per-process CPU and memory | via `libproc` — import Darwin. No entitlements required for basic process listing |
| `mach_host_statistics` | Physical memory statistics (vm_statistics64) | Mach kernel call, pure C bridging in Swift |
| `IOKit` (IOServiceGetMatchingServices) | Disk I/O stats, battery, optional SMC for temperature | Requires IOKit framework linkage. SMC access works without special entitlements for reading |
| `Darwin.statvfs` | Disk space (free/used/total per volume) | Single syscall, always available, no entitlements |
| `apple/swift-system-metrics` | Process-level self-monitoring (daemon's own CPU/memory) | Use for the daemon to report its own resource usage only. Not suitable for system-wide CPU/RAM monitoring — it measures the calling process, not the whole system |
| `Foundation.Process` | Execute shell commands (diskutil, brew, launchctl, kill) | Shell out for repair actions — `diskutil verifyPermissions`, `brew upgrade`, `launchctl kickstart` |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-argument-parser | 1.7.0 | CLI subcommands (start/stop/status/logs) | For the daemon entry point and any CLI management wrapper. Apple-maintained, standard for Swift CLI tools. |
| apple/swift-system-metrics | 1.0.1 | Daemon self-diagnostics | Use only to expose the daemon's own memory/CPU consumption in the dashboard. Released Feb 2026 — stable API. |
| HummingbirdWebSocket | same as Hummingbird | WebSocket for live dashboard push | Hummingbird extension. Push real-time metric updates to browser without polling. Pull in only when implementing live dashboard. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode 16+ | Build, debug, code-sign | Required for macOS entitlements and codesigning. Daemon must be signed to avoid Gatekeeper issues on newer macOS. |
| Swift Package Manager | Dependency management | No CocoaPods or Carthage — SPM is the only supported PM for server-side Swift packages |
| `launchctl` (CLI) | Load/unload/inspect the LaunchAgent during dev | Use `launchctl print gui/$(id -u)/com.guardian.daemon` to debug |
| Console.app | View OSLog output | Filter by subsystem (your bundle ID) for clean daemon log view |
| `log stream` | Real-time OSLog from terminal | `log stream --predicate 'subsystem=="com.guardian.daemon"' --level debug` |

---

## Installation

```bash
# Package.swift dependencies
# Add to your Package.swift:

.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
.package(url: "https://github.com/hummingbird-project/hummingbird-websocket.git", from: "2.0.0"),
.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
.package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
.package(url: "https://github.com/apple/swift-system-metrics.git", from: "1.0.0"),
```

```bash
# Build the daemon binary
swift build -c release

# Install LaunchAgent plist (after building)
cp .build/release/macos-guardian ~/Library/LaunchAgents/
# Edit com.guardian.daemon.plist with correct binary path
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.guardian.daemon.plist
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Swift | Go | Only if you need cross-platform and don't need native IOKit/SMC access. Go's gopsutil works on macOS but only via shell-out or limited APIs — no IOKit. |
| Swift | Python | For quick throwaway scripts only. Python is too heavyweight as a persistent daemon and requires runtime management. Homebrew Python version changes break daemons. |
| Hummingbird | Vapor | Only if project grows to need full Vapor ecosystem (auth, ORM, jobs queue). For localhost-only dashboard, Vapor's binary size and compile overhead is unjustified. |
| GRDB.swift | SQLite.swift | SQLite.swift is fine too, but GRDB has better async support and Swift 6 concurrency safety. Either works. |
| GRDB.swift | Core Data | Never for a daemon. Core Data is NSPersistentContainer tied to AppKit/UIKit patterns — wrong tool for a headless CLI process. |
| OSLog | File-based logging | Only if you need log portability. OSLog is more searchable, has privacy controls, and requires zero file rotation logic. For a local daemon, OSLog is strictly better. |
| LaunchAgent | LaunchDaemon | Use LaunchDaemon (system-level) only if you need to run before user login or as root continuously. LaunchAgent runs as the user, which is correct here — dashboard, process killing, Homebrew updates all need user context. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| beltex/SystemKit | Unmaintained (last commit 2017), Swift 3 era, no async support, Swift Package Manager issues | Copy the sysctl/IOKit patterns from its source code directly into your project |
| Python + psutil | Python daemon startup latency, runtime version instability, no native IOKit access, Homebrew Python changes can silently break daemon | Swift with Darwin sysctl calls |
| Node.js | No native macOS system API access, requires managing a JS runtime, wrong tool for system-level work | Swift |
| Vapor | 30+ transitive dependencies, large binary, full-stack ORM included — all overkill for a single-machine localhost dashboard | Hummingbird 2 |
| swift-log file backend | Duplicates what OSLog already does, adds log rotation complexity | Use OSLog directly via `import OSLog` and `Logger(subsystem:category:)` |
| XPC services | Only needed if you need privilege separation between components. Adds significant complexity. For this project scope, a single process running as user with appropriate TCC permissions is sufficient | Single process architecture with Foundation.Process for privileged shell commands |
| Timer-based concurrency (DispatchSourceTimer, Timer) | Deprecated concurrency patterns in Swift 6. Data races, hard to reason about shutdown | Swift Structured Concurrency: `withTaskGroup` + `try await Task.sleep(for:)` polling loops |

---

## Stack Patterns by Variant

**If you need process kill/restart with elevated permissions:**
- Use `Foundation.Process` to call `kill(pid, SIGTERM)` — available without special entitlements for user-owned processes
- For system processes, use `launchctl kickstart -k` via shell-out
- Do NOT attempt to write to TCC database or bypass SIP — will be silently rejected or cause daemon termination

**If you need temperature/fan monitoring:**
- Use IOKit SMC access patterns from exelban/stats open source code (MIT licensed reference)
- Temperature read does NOT require special entitlements
- Fan control DOES require root — out of scope for this daemon

**If dashboard needs authentication:**
- Add `HummingbirdAuth` extension to Hummingbird
- But for localhost-only: no auth needed (localhost is trusted)

**If you need to watch for file system changes:**
- Use `DispatchSource.makeFileSystemObjectSource` or `FSEvents` via CoreServices framework
- Relevant for watching LaunchAgent plist directories for orphaned agents

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Hummingbird 2.20.1 | Swift 5.10+, macOS 13+ | Swift 6 mode recommended |
| GRDB 7.10.0 | Swift 6.1+, macOS 10.15+ | Full Swift 6 concurrency safety |
| swift-service-lifecycle 2.10.1 | Swift 5.9+, macOS 12+ | Integrated with Hummingbird by default |
| swift-argument-parser 1.7.0 | Swift 5.9+, macOS 10.15+ | |
| swift-system-metrics 1.0.1 | Swift 5.9+, macOS 13+ | Process-level only, not system-wide |
| Target OS | macOS 15.x (Darwin 25.4.0) | User is running Sequoia. No compatibility constraints to worry about — can use all modern APIs. |

---

## macOS Security Model Notes

**SIP (System Integrity Protection):** Active on user's machine. Daemon must NOT attempt to:
- Modify `/System`, `/usr`, `/bin`, `/sbin` — blocked by SIP
- Load unsigned kernel extensions
- Write to protected plist files in `/Library/LaunchDaemons`

Daemon CAN:
- Kill user processes (without special entitlements)
- Restart user-owned LaunchAgents (`launchctl kickstart`)
- Read disk stats, process lists, CPU/RAM metrics
- Shell out to `diskutil`, `brew`, `launchctl`

**TCC (Transparency, Consent, Control):** User must grant "Full Disk Access" in System Settings if daemon needs to read files in protected directories (Documents, Downloads, Desktop). This is a one-time grant via the GUI — document in setup instructions.

**Code Signing:** Binary must be signed (can be ad-hoc for personal use) to avoid Gatekeeper prompts. For distribution, Developer ID signing is required.

---

## Sources

- [Announcing Swift System Metrics 1.0 — Swift.org](https://www.swift.org/blog/swift-system-metrics-1.0-released/) — HIGH confidence, official Apple announcement Feb 2026
- [apple/swift-system-metrics GitHub](https://github.com/apple/swift-system-metrics) — version 1.0.1, macOS 13+
- [hummingbird-project/hummingbird GitHub](https://github.com/hummingbird-project/hummingbird) — version 2.20.1 (Feb 2026)
- [groue/GRDB.swift GitHub](https://github.com/groue/GRDB.swift) — version 7.10.0 (Feb 2026), Swift 6.1+ — HIGH confidence
- [swift-server/swift-service-lifecycle GitHub](https://github.com/swift-server/swift-service-lifecycle) — version 2.10.1 (Feb 2026)
- [apple/swift-argument-parser GitHub](https://github.com/apple/swift-argument-parser) — version 1.7.0 — HIGH confidence
- [apple/swift-log GitHub](https://github.com/apple/swift-log) — version 1.10.1 (Feb 2026)
- [OSLog Apple Developer Documentation](https://developer.apple.com/documentation/OSLog) — official, HIGH confidence
- [IOKit Apple Developer Documentation](https://developer.apple.com/documentation/iokit) — official
- [exelban/stats — Open source reference for IOKit/SMC patterns](https://github.com/exelban/stats) — MEDIUM confidence (real-world usage patterns)
- [Swift 6.2 Released — Swift.org](https://www.swift.org/blog/swift-6.2-released/) — HIGH confidence
- [Hummingbird vs Vapor comparison — GitHub Discussions](https://github.com/hummingbird-project/hummingbird/discussions/150) — MEDIUM confidence
- [SIP documentation — Apple Support](https://support.apple.com/en-us/102149) — official, HIGH confidence
- [launchd.plist man page](https://keith.github.io/xcode-man-pages/launchd.plist.5.html) — HIGH confidence

---

*Stack research for: macOS system monitoring daemon (macOS Guardian)*
*Researched: 2026-03-03*
