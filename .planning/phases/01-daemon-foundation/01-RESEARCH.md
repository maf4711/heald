# Phase 1: Daemon Foundation - Research

**Researched:** 2026-03-03
**Domain:** macOS LaunchAgent daemon lifecycle — Swift 6, swift-service-lifecycle, launchd plist, Homebrew install scripting
**Confidence:** HIGH (core stack and launchd patterns verified via official docs and upstream GitHub; Ollama install MEDIUM)

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| DAEM-01 | Daemon laeuft persistent als LaunchAgent (startet bei Login, ueberlebt Reboot) | LaunchAgent plist with `KeepAlive: true` + `RunAtLoad: true`; `launchctl bootstrap` on install |
| DAEM-02 | Daemon behandelt SIGTERM von launchd sauber ohne Datenverlust | swift-service-lifecycle `ServiceGroup` with `gracefulShutdownSignals: [.sigterm]`; `gracefulShutdown()` suspension point in each `Service.run()` |
| DAEM-03 | Daemon verbraucht selbst minimal CPU/RAM (< 1% CPU, < 50MB RAM im Idle) | Plist `ProcessType: Background`, `LowPriorityIO: true`, `Nice: 5`; no busy-loop; idle = just the run loop sleeping |
| DAEM-04 | Install-Script installiert alle Abhaengigkeiten via Homebrew (inkl. Ollama) | `brew install ollama` (formula, CLI); `swift build -c release`; `launchctl bootstrap gui/$(id -u)` |
| DAEM-05 | Uninstall-Script entfernt Daemon und LaunchAgent sauber | `launchctl bootout gui/$(id -u)`; remove plist + binary; `brew uninstall ollama` optional |

</phase_requirements>

---

## Summary

Phase 1 establishes a Swift 6 executable that runs as a macOS LaunchAgent: it starts at login, is kept alive by launchd, shuts down cleanly on SIGTERM, and consumes negligible resources while idle. The daemon itself has no monitoring logic in this phase — it is purely the process skeleton that later phases wire into.

The standard mechanism is a three-part system: (1) a Swift `@main` entry point using `swift-service-lifecycle`'s `ServiceGroup`, (2) a `launchd.plist` file in `~/Library/LaunchAgents/` with `KeepAlive: true`, and (3) an `install.sh` that builds the binary, places the plist, and calls `launchctl bootstrap gui/$(id -u)`. The critical correctness requirement is that SIGTERM — sent by launchd when the user logs out or when `launchctl bootout` is called — triggers a clean exit through swift-service-lifecycle's graceful shutdown path, confirmed by an OSLog entry before `exit(0)`.

The project target is macOS Sequoia (Darwin 25.4.0, Apple Silicon). All modern APIs are available with no back-compat constraints. Ollama is installed via `brew install ollama` (CLI formula, not the GUI cask). The install script must NOT run `brew` as root — Homebrew blocks root execution.

**Primary recommendation:** Use `swift-service-lifecycle` `ServiceGroup` with `gracefulShutdownSignals: [.sigterm]`. Every service's `run()` suspends on `gracefulShutdown()`. Verify with a cold reboot test (not just `launchctl bootstrap`).

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift | 6.x (6.2 toolchain) | Language | Native macOS APIs; Swift 6 structured concurrency maps cleanly to daemon polling loop; no bridging overhead |
| swift-service-lifecycle | 2.10.1 | SIGTERM handling, startup/shutdown orchestration | Provides `ServiceGroup` which wires POSIX signals to async task cancellation; Hummingbird depends on it; zero extra cost |
| OSLog (system framework) | Bundled with macOS | Structured logging | Zero dependency; persisted to `/var/db/diagnostics`; searchable in Console.app and `log` CLI; no file rotation required |
| swift-argument-parser | 1.7.0 | CLI entry point flags | Phase 1 needs at minimum `--version` and clean arg parsing; Apple-maintained |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| apple/swift-system-metrics | 1.0.1 | Daemon self-resource reporting | Phase 1 can optionally expose own CPU/RAM via OSLog to validate DAEM-03; process-level only |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| swift-service-lifecycle | Manual `signal()` / `DispatchSource.makeSignalSource` | Manual signal handling misses graceful shutdown semantics and task group coordination; swift-service-lifecycle is already in the dependency tree via Hummingbird |
| OSLog | swift-log + file backend | OSLog is already integrated into macOS unified logging; file backend adds rotation complexity with no benefit for a local daemon |
| LaunchAgent | LaunchDaemon (root) | LaunchDaemon cannot access user session, GUI apps, or run Homebrew as user — explicitly ruled out by project decisions |

**Installation:**
```bash
# Package.swift dependencies
.package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
.package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),

# Build
swift build -c release

# Install
cp .build/release/heald ~/Library/heald/heald
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.heald.daemon.plist
```

---

## Architecture Patterns

### Recommended Project Structure (Phase 1 scope only)

```
heald/
├── Package.swift                        # Swift 6 executable target, macOS 15 min
├── Sources/
│   └── heald/
│       ├── main.swift                   # @main entry point, ServiceGroup setup
│       ├── HealdService.swift           # Core Service conforming type (idle loop in phase 1)
│       └── Logging.swift               # OSLog subsystem/category constants
├── launchd/
│   └── com.heald.daemon.plist          # LaunchAgent template (relative paths replaced at install)
├── install.sh                          # Build + deploy + launchctl bootstrap
└── uninstall.sh                        # launchctl bootout + file removal
```

### Pattern 1: ServiceGroup with SIGTERM as Graceful Shutdown

**What:** `ServiceGroup` catches SIGTERM and calls graceful shutdown on all registered `Service` types. Each service's `run()` method suspends on `gracefulShutdown()` — when launchd sends SIGTERM, the suspension returns and the service cleans up.

**When to use:** Always — this is the Phase 1 core pattern. Later phases add services to the same `ServiceGroup`.

**Example:**
```swift
// Source: https://github.com/swift-server/swift-service-lifecycle/blob/main/README.md
import ServiceLifecycle
import OSLog

private let logger = Logger(subsystem: "com.heald.daemon", category: "lifecycle")

@main
struct HealdApp {
    static func main() async throws {
        let service = HealdService()

        let serviceGroup = ServiceGroup(
            services: [service],
            gracefulShutdownSignals: [.sigterm],
            logger: .init(label: "com.heald.daemon")
        )

        logger.info("heald starting")
        try await serviceGroup.run()
        logger.info("heald stopped cleanly")
    }
}
```

### Pattern 2: Service Conforming Type with Graceful Shutdown Suspension

**What:** The `Service` protocol requires a single `run() async throws` method. The service suspends on `gracefulShutdown()` — this returns when the `ServiceGroup` initiates graceful shutdown. Cleanup happens after the suspension returns.

**When to use:** Every service type in the daemon must follow this pattern. In Phase 1 the `HealdService` is an idle loop. In later phases, monitoring collectors, the HTTP server, etc. are each their own `Service`.

**Example:**
```swift
// Source: https://swiftonserver.com/introduction-to-swift-service-lifecycle/
import ServiceLifecycle
import OSLog

private let logger = Logger(subsystem: "com.heald.daemon", category: "core")

struct HealdService: Service {
    func run() async throws {
        logger.info("HealdService running — idle loop (phase 1 skeleton)")

        // Pattern A: suspend until graceful shutdown is requested
        try await gracefulShutdown()

        // Pattern B (for services with a work loop):
        // try await withGracefulShutdownHandler {
        //     for try await _ in someAsyncSequence { /* work */ }
        // } onGracefulShutdown: {
        //     logger.info("shutdown requested — draining")
        //     someAsyncSequence.finish()
        // }

        logger.info("HealdService shutting down cleanly")
    }
}
```

### Pattern 3: LaunchAgent Plist for User-Context Daemon

**What:** A plist file in `~/Library/LaunchAgents/` that launchd loads at user login. `KeepAlive: true` ensures the process is restarted if it crashes. `ProcessType: Background` and `LowPriorityIO: true` prevent the daemon from competing with foreground work.

**When to use:** Always — this is the required deployment mechanism for DAEM-01.

**Example:**
```xml
<!-- Source: https://launchd.info/ + https://keith.github.io/xcode-man-pages/launchd.plist.5.html -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.heald.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <!-- ABSOLUTE PATH — filled in by install.sh -->
        <string>/Users/USERNAME/Library/heald/heald</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>Nice</key>
    <integer>5</integer>
    <key>StandardOutPath</key>
    <string>/tmp/heald.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/heald.err.log</string>
</dict>
</plist>
```

### Pattern 4: Install Script Pattern

**What:** `install.sh` builds the release binary, creates the install directory, writes the plist with the user's actual home path, and bootstraps the LaunchAgent. Must run as the current user (not root) because Homebrew refuses root execution.

**Example:**
```bash
#!/usr/bin/env bash
set -euo pipefail

LABEL="com.heald.daemon"
INSTALL_DIR="$HOME/Library/heald"
BINARY="$INSTALL_DIR/heald"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
USER_ID=$(id -u)

# 1. Install Homebrew dependencies
if ! command -v brew &>/dev/null; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to PATH for Apple Silicon
    eval "$(/opt/homebrew/bin/brew shellenv)" 2>/dev/null || eval "$(/usr/local/bin/brew shellenv)"
fi

brew install ollama

# 2. Build daemon
swift build -c release
mkdir -p "$INSTALL_DIR"
cp .build/release/heald "$BINARY"
chmod 755 "$BINARY"

# 3. Write plist with absolute path
sed "s|USERNAME|$(whoami)|g" launchd/com.heald.daemon.plist > "$PLIST"

# 4. Validate plist
plutil -lint "$PLIST"

# 5. Bootstrap (unload first if already loaded)
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${USER_ID}" "$PLIST"

echo "heald installed. Verify: launchctl list | grep heald"
```

### Pattern 5: Uninstall Script Pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

LABEL="com.heald.daemon"
USER_ID=$(id -u)

launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/${LABEL}.plist"
rm -rf "$HOME/Library/heald"

echo "heald uninstalled."
# Note: brew uninstall ollama is intentionally NOT done by default
# to avoid removing a tool the user may use independently.
```

### Anti-Patterns to Avoid

- **`launchctl load` / `launchctl unload` (deprecated):** Replaced by `launchctl bootstrap` / `launchctl bootout` since macOS 10.11. The old commands are removed or silently broken on newer macOS. Use `bootstrap`/`bootout` exclusively.
- **Relative paths in ProgramArguments:** launchd requires absolute paths. At boot, the working directory is undefined. Template the plist with the user's actual `$HOME` at install time.
- **Testing only with `launchctl bootstrap` (no reboot test):** launchd applies stricter rules at boot than during manual load. Always test with a cold reboot as the acceptance gate for DAEM-01.
- **`Disabled: true` in plist:** This key is overridden by `/var/db/com.apple.xpc.launchd/disabled.plist` and can cause the agent to fail to load after reboot silently. Do not include this key.
- **Signal handling with `DispatchSource.makeSignalSource` instead of swift-service-lifecycle:** In Swift 6 structured concurrency, dispatch sources for signals are a deprecated pattern. `ServiceGroup` handles signals in an actor-isolated, race-free way.
- **Running install.sh as root:** Homebrew explicitly blocks root execution (`Error: Running Homebrew as root is extremely dangerous and no longer supported`). The LaunchAgent itself runs as the current user — root is never needed.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SIGTERM → clean exit coordination | Custom signal handler + global flags | swift-service-lifecycle `ServiceGroup` | Structured concurrency-safe; handles ordering of multiple services; avoids race conditions on shutdown |
| Daemon restart on crash | Custom watchdog process | launchd `KeepAlive: true` in plist | launchd is the OS-level supervisor; it tracks crash vs. clean exit and can be configured separately via `KeepAlive` dict with `Crashed: true` |
| Crash-loop prevention | Custom retry backoff logic | launchd `ThrottleInterval` | Single plist key; launchd enforces it system-wide before relaunching |
| Plist path validation at install | Custom XML parser | `plutil -lint` | Built into macOS; catches malformed plist before launchd rejects it silently |
| Homebrew presence detection | Custom file existence checks | `command -v brew` in install.sh | Standard POSIX; works on both Intel (`/usr/local/bin/brew`) and Apple Silicon (`/opt/homebrew/bin/brew`) |

**Key insight:** launchd already provides everything needed for a production-grade process supervisor. The daemon does not need its own watchdog, restart logic, or signal management infrastructure — it just needs to exit cleanly on SIGTERM and let launchd handle the rest.

---

## Common Pitfalls

### Pitfall 1: LaunchAgent Not Loading After Cold Reboot

**What goes wrong:** Agent loads fine with `launchctl bootstrap` during development but is missing after a fresh reboot. `launchctl list | grep heald` returns nothing.

**Why it happens:** Most commonly one of: (a) plist file has wrong permissions, (b) plist contains a relative path in `ProgramArguments`, (c) binary path doesn't exist at load time, or (d) `Disabled` key inadvertently set. launchd silently skips plists with dubious ownership or paths at boot.

**How to avoid:**
- Validate with `plutil -lint` before installing
- Always use absolute paths in `ProgramArguments`
- Set plist permissions: `chmod 644 "$PLIST"` (user-owned is correct for LaunchAgent)
- Do not include the `Disabled` key in the plist template
- Accept criterion: cold reboot + `launchctl list | grep heald` — not just a manual bootstrap test

**Warning signs:** Agent works after `launchctl bootstrap` but disappears after logout/login cycle.

### Pitfall 2: SIGTERM Not Producing a Log Entry (Silent Exit)

**What goes wrong:** DAEM-02 success criterion requires a "confirmation log entry" on SIGTERM. The daemon exits but OSLog shows nothing from the shutdown path.

**Why it happens:** The `gracefulShutdown()` suspension returns, the `run()` method returns, but the OSLog write at the end of `main()` never completes because `Logger` flushes asynchronously and the process exits before the flush.

**How to avoid:**
- Write the shutdown log entry BEFORE awaiting `serviceGroup.run()` to return — use `onGracefulShutdown:` callback inside the service, not in `main()` after `try await serviceGroup.run()`
- Use `os_log()` C function (synchronous) for the final shutdown log if needed, not `Logger` (async)
- Test: send SIGTERM, then immediately run `log show --predicate 'subsystem=="com.heald.daemon"' --last 1m` to confirm the entry exists

**Warning signs:** OSLog shows startup entry but no shutdown entry.

### Pitfall 3: Crash Loop Without ThrottleInterval

**What goes wrong:** A bug in the daemon causes it to crash immediately on startup. launchd respects `KeepAlive: true` and relaunches it immediately. Without `ThrottleInterval`, launchd spins the process at 100% CPU in a tight restart loop, consuming a full core until the user intervenes.

**Why it happens:** `KeepAlive: true` without `ThrottleInterval` defaults to a very short respawn delay (launchd default: 1 second). A startup crash cycles fast enough to saturate a core.

**How to avoid:** Always set `ThrottleInterval` to at least 10 seconds in the plist. This is already shown in the recommended plist template above.

**Warning signs:** `launchctl list com.heald.daemon` shows a rapidly incrementing `LimitLoadToSessionType` or `OnDemand` counter; machine becomes sluggish.

### Pitfall 4: Homebrew Runs as Root During Install

**What goes wrong:** `install.sh` is run with `sudo` (user assumes root is needed for system installation). Homebrew detects root and exits with an error, causing the install to fail mid-script.

**Why it happens:** Historically some tools required sudo for system-wide installation. Homebrew explicitly forbids root execution to protect the user's toolchain.

**How to avoid:**
- Document clearly: `./install.sh` must NOT be run with sudo
- The daemon binary and plist are installed into `~/Library/` (user home), not system paths — no root required
- The `set -euo pipefail` in the install script causes it to fail immediately if brew exits with an error, catching this early

**Warning signs:** Install script exits with "Running Homebrew as root is extremely dangerous and no longer supported."

### Pitfall 5: CPU/RAM Exceeding Idle Budget (DAEM-03)

**What goes wrong:** The Phase 1 daemon skeleton exceeds < 1% CPU or < 50MB RAM without any monitoring work running.

**Why it happens:** Swift runtime overhead, SwiftNIO event loop (if pulled in via Hummingbird before it's needed), or a busy-loop in `run()` without a proper `await` suspension.

**How to avoid:**
- Phase 1 daemon has NO Hummingbird dependency — the HTTP server is Phase 4 work
- The idle `HealdService.run()` must actually suspend (via `gracefulShutdown()`) — verify there is no busy loop
- Set `ProcessType: Background` and `LowPriorityIO: true` in the plist
- Measure with `ps -o %cpu,rss -p $(pgrep heald)` after 5 minutes of running

**Warning signs:** Activity Monitor shows > 0.1% CPU sustained for a process doing nothing.

---

## Code Examples

Verified patterns from official sources:

### Package.swift for Phase 1 (No Hummingbird Yet)

```swift
// Source: https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "heald",
    platforms: [
        .macOS(.v15)  // Target: macOS Sequoia
    ],
    dependencies: [
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "heald",
            dependencies: [
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
```

### OSLog Setup for heald

```swift
// Source: https://developer.apple.com/documentation/OSLog
import OSLog

// Centralized logger constants — one file, imported everywhere
extension Logger {
    static let lifecycle = Logger(subsystem: "com.heald.daemon", category: "lifecycle")
    static let core      = Logger(subsystem: "com.heald.daemon", category: "core")
    // Phase 2 will add: .collector, .analyzer, .healer
}

// Usage:
// Logger.lifecycle.info("heald starting — version \(version)")
// Logger.lifecycle.info("heald stopped cleanly")
```

### Verifying LaunchAgent Status

```bash
# Check agent is loaded and running
launchctl list | grep heald
# Output: PID   0   com.heald.daemon
# PID > 0 means running; PID = "-" means loaded but not running

# Full detail
launchctl print gui/$(id -u)/com.heald.daemon

# Watch OSLog in real time
log stream --predicate 'subsystem=="com.heald.daemon"' --level debug

# View recent OSLog (after reboot / SIGTERM test)
log show --predicate 'subsystem=="com.heald.daemon"' --last 5m
```

### SIGTERM Test (for DAEM-02 validation)

```bash
# Trigger clean shutdown
launchctl kill SIGTERM gui/$(id -u)/com.heald.daemon

# Confirm log entry exists
log show --predicate 'subsystem=="com.heald.daemon" AND eventMessage CONTAINS "stopped cleanly"' --last 1m
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `launchctl load/unload` | `launchctl bootstrap/bootout` | macOS 10.11 (El Capitan) | Old commands deprecated/removed; new commands required for Sequoia |
| `signal()` / `DispatchSourceSignal` for SIGTERM | `ServiceGroup(gracefulShutdownSignals:)` | Swift 5.9 (swift-service-lifecycle v2) | Structured concurrency-safe; eliminates signal race conditions |
| `/etc/periodic` for scheduled tasks | launchd plist scheduling | macOS 15 Sequoia | `periodic` binary removed in Sequoia; launchd-only for scheduling |
| Custom file-based log rotation | OSLog unified logging | macOS 10.12 | OS manages retention automatically; zero configuration |
| `Timer` / `DispatchSourceTimer` for polling loops | `Task.sleep(for:)` in async context | Swift 5.5 (async/await) | Data-race free; cancellation propagates correctly through task tree |

**Deprecated/outdated:**
- `launchctl load/unload`: Do not use. Removed on Sequoia for many contexts.
- `DispatchSource.makeSignalSource` as primary signal handler: Works but bypasses Swift 6 structured concurrency guarantees.
- `/etc/periodic`: Removed in macOS 15. Use launchd plists with `StartInterval` or `StartCalendarInterval`.
- `beltex/SystemKit`: Last commit 2017, Swift 3 era — copy patterns, do not import.

---

## Open Questions

1. **swift-service-lifecycle SIGTERM vs SIGINT for development**
   - What we know: `gracefulShutdownSignals: [.sigterm]` catches launchd's signal. During development, Ctrl+C sends SIGINT.
   - What's unclear: Should the service group also include SIGINT as a graceful shutdown signal for developer ergonomics, or should SIGINT be a `cancellationSignal` (immediate stop)?
   - Recommendation: Use `gracefulShutdownSignals: [.sigterm, .sigint]` for Phase 1 skeleton. Adjust in later phases if SIGINT needs to be a hard kill during development.

2. **Ollama formula vs. cask for daemon use**
   - What we know: `brew install ollama` installs the CLI formula (no GUI); `brew install --cask ollama-app` installs the GUI app. For a daemon that calls Ollama programmatically, the formula is correct.
   - What's unclear: Whether the formula installs an Ollama service that starts automatically or needs `ollama serve` to be called by the daemon.
   - Recommendation: Use `brew install ollama` (formula). The daemon will be responsible for starting Ollama when needed (Phase 7). For Phase 1, just install the formula.

3. **Binary install location**
   - What we know: The daemon must not be installed in Homebrew-managed paths (`/opt/homebrew/bin`) to avoid privilege escalation, but it also runs as the user (not root) so the security concern from PITFALLS.md (Pitfall 5: LaunchDaemon hijacking) applies less severely to a LaunchAgent.
   - What's unclear: Best location for a user-context LaunchAgent binary — `~/Library/heald/heald` (per-user Application Support pattern) or `~/.local/bin/heald` (POSIX user binary convention)?
   - Recommendation: Use `~/Library/heald/heald`. Matches macOS conventions for user-installed app support files. Clean to uninstall (remove the directory).

---

## Sources

### Primary (HIGH confidence)

- [swift-server/swift-service-lifecycle GitHub](https://github.com/swift-server/swift-service-lifecycle/blob/main/README.md) — ServiceGroup API, signal configuration, version 2.10.1
- [swift-service-lifecycle releases](https://github.com/swift-server/swift-service-lifecycle/releases) — confirmed 2.10.1 as latest (Feb 2024)
- [launchd.plist man page](https://keith.github.io/xcode-man-pages/launchd.plist.5.html) — ProcessType, LowPriorityIO, Nice, ThrottleInterval, KeepAlive
- [launchd.info](https://launchd.info/) — `launchctl bootstrap`/`bootout` syntax, LaunchAgent patterns
- [Apple OSLog documentation](https://developer.apple.com/documentation/OSLog) — Logger(subsystem:category:) API
- [Swift Package Manager documentation](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html) — platforms: [.macOS(.v15)] syntax

### Secondary (MEDIUM confidence)

- [swiftonserver.com — Introduction to Swift Service Lifecycle](https://swiftonserver.com/introduction-to-swift-service-lifecycle/) — gracefulShutdown() and withGracefulShutdownHandler patterns with code examples; cross-verified with GitHub README
- [Homebrew formulae — ollama](https://formulae.brew.sh/formula/ollama) — version 0.17.5, confirmed formula (not cask)
- [Homebrew installation docs](https://docs.brew.sh/Installation) — Apple Silicon path `/opt/homebrew/bin/brew`, detection pattern
- [swift-service-lifecycle Swift Forums thread](https://forums.swift.org/t/new-servicelifecycle-apis/65521) — gracefulShutdownSignals vs cancellationSignals design rationale

### Tertiary (LOW confidence — verify if critical)

- [alan siu blog — launchctl new subcommand basics](https://www.alansiu.net/2023/11/15/launchctl-new-subcommand-basics-for-macos/) — helpful overview of bootstrap/bootout; single source, not Apple official

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — swift-service-lifecycle and OSLog are confirmed via GitHub releases and official Apple docs; versions verified
- Architecture: HIGH — LaunchAgent patterns are stable macOS fundamentals; verified via man pages and launchd.info
- Pitfalls: HIGH — cold reboot requirement, ThrottleInterval, deprecated launchctl commands all verified via official sources
- Ollama install: MEDIUM — formula vs. cask distinction confirmed via Homebrew formulae; daemon invocation pattern inferred (verify in Phase 7)

**Research date:** 2026-03-03
**Valid until:** 2026-06-03 (90 days — stack is stable; launchd patterns are macOS-version-tied and Sequoia is not changing)
