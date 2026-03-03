---
phase: 01-daemon-foundation
plan: 01
subsystem: infra
tags: [swift, swift6, servicelifecycle, argumentparser, oslog, launchd, launchagent]

# Dependency graph
requires: []
provides:
  - Buildable Swift 6 executable package at heald/ targeting macOS 15
  - Graceful SIGTERM/SIGINT shutdown via ServiceLifecycle ServiceGroup
  - Centralized OSLog logging (subsystem com.heald.daemon, categories lifecycle/core)
  - LaunchAgent plist template with KeepAlive, ThrottleInterval, ProcessType Background
affects:
  - 01-daemon-foundation
  - 02-monitoring
  - 03-storage
  - 04-cloud-dashboard
  - 05-healer

# Tech tracking
tech-stack:
  added:
    - swift-service-lifecycle 2.x (ServiceGroup, withGracefulShutdownHandler)
    - swift-argument-parser 1.7.x (AsyncParsableCommand, --version flag)
    - OSLog (structured logging, subsystem/category model)
  patterns:
    - top-level main.swift calls Command.main() to avoid @main/main.swift conflict in Swift 6
    - withGracefulShutdownHandler used inside Service.run() to guarantee shutdown log before process exits
    - Logger extension for centralized OSLog constants (no per-file Logger construction)

key-files:
  created:
    - heald/Package.swift
    - heald/Sources/heald/main.swift
    - heald/Sources/heald/HealdApp.swift
    - heald/Sources/heald/HealdService.swift
    - heald/Sources/heald/Logging.swift
    - heald/launchd/com.heald.daemon.plist
  modified: []

key-decisions:
  - "Use main.swift top-level call (HealdApp.main()) instead of @main to satisfy Swift 6 compiler constraint — @main conflicts with top-level code in main.swift"
  - "Shutdown log written inside onGracefulShutdown callback of withGracefulShutdownHandler, not after serviceGroup.run() returns — guarantees OSLog flush before process exit"
  - "static var configuration changed to static let — Swift 6 strict concurrency rejects nonisolated mutable global state"

patterns-established:
  - "Logger extension pattern: all OSLog loggers declared as static let on Logger extension in Logging.swift — no per-file Logger construction"
  - "Service conformance pattern: HealdService.run() uses withGracefulShutdownHandler for true suspension + guaranteed shutdown callback"
  - "AsyncParsableCommand pattern: struct conforms to AsyncParsableCommand, entry via top-level main.swift calling Command.main()"

requirements-completed: [DAEM-01, DAEM-02, DAEM-03]

# Metrics
duration: 2min
completed: 2026-03-03
---

# Phase 1 Plan 01: Daemon Foundation Summary

**Swift 6 heald daemon skeleton with ServiceLifecycle graceful shutdown, OSLog centralized logging, and LaunchAgent plist template — builds cleanly for macOS 15 release target**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-03T04:33:07Z
- **Completed:** 2026-03-03T04:34:54Z
- **Tasks:** 2
- **Files modified:** 6 created

## Accomplishments

- Swift 6 executable package resolving swift-service-lifecycle and swift-argument-parser, passes `swift build -c release` with no errors or warnings
- HealdService with `withGracefulShutdownHandler` providing true Task.sleep suspension (0% CPU idle), guaranteed shutdown log on SIGTERM/SIGINT
- LaunchAgent plist template with all required launchd keys: KeepAlive, RunAtLoad, ThrottleInterval 10s, ProcessType Background, LowPriorityIO, Nice 5, no Disabled key

## Task Commits

Each task was committed atomically:

1. **Task 1: Initialize Swift package with dependencies and directory structure** - `257be0a` (feat)
2. **Task 2: Create LaunchAgent plist template** - `ab71270` (feat)

**Plan metadata:** (pending — docs commit below)

## Files Created/Modified

- `heald/Package.swift` - Swift 6 package manifest, macOS 15 min, two deps, one executable target
- `heald/Sources/heald/main.swift` - Top-level entry point calling HealdApp.main()
- `heald/Sources/heald/HealdApp.swift` - AsyncParsableCommand with --version, ServiceGroup wiring
- `heald/Sources/heald/HealdService.swift` - Service-conforming idle skeleton with graceful shutdown handler
- `heald/Sources/heald/Logging.swift` - Centralized OSLog Logger extension (lifecycle, core categories)
- `heald/launchd/com.heald.daemon.plist` - LaunchAgent template with USERNAME placeholder

## Decisions Made

- Used `HealdApp.main()` call in `main.swift` instead of `@main` attribute — Swift 6 rejects `@main` in a module containing a `main.swift` file (top-level code conflict). The ArgumentParser pattern of calling `.main()` from top-level code in `main.swift` is the correct approach for Swift executables.
- Changed `static var configuration` to `static let` — Swift 6 strict concurrency treats `var` as nonisolated mutable global shared state, which is an error. `CommandConfiguration` is a value type, `let` is correct.
- Shutdown log placed inside `onGracefulShutdown` callback rather than after `serviceGroup.run()` — OSLog writes are asynchronous; the process may exit before the flush if the log is written post-run.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Swift 6 concurrency error: `static var configuration` → `static let`**
- **Found during:** Task 1 (build verification)
- **Issue:** Swift 6 strict concurrency rejects `static var` on a struct as nonisolated mutable global shared mutable state
- **Fix:** Changed `static var configuration` to `static let configuration` — `CommandConfiguration` is a struct (value type), `let` is both correct and sufficient
- **Files modified:** heald/Sources/heald/HealdApp.swift (formerly main.swift)
- **Verification:** `swift build` exits 0 with Build complete
- **Committed in:** 257be0a (Task 1 commit)

**2. [Rule 1 - Bug] Fixed `@main` / `main.swift` conflict in Swift 6**
- **Found during:** Task 1 (build verification after first fix)
- **Issue:** `@main struct HealdApp` in a file named `main.swift` causes Swift compiler error: "main attribute cannot be used in a module that contains top-level code" — `main.swift` is implicitly treated as the top-level entry point
- **Fix:** Renamed `main.swift` to `HealdApp.swift`, removed `@main`, created a minimal `main.swift` with `HealdApp.main()` — the standard ArgumentParser pattern for Swift executables
- **Files modified:** heald/Sources/heald/HealdApp.swift (new name), heald/Sources/heald/main.swift (new minimal file)
- **Verification:** `swift build` and `swift build -c release` both exit 0
- **Committed in:** 257be0a (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — Swift 6 compiler errors)
**Impact on plan:** Both fixes were necessary for compilation. No scope creep. The plan specified `@main` and `static var` patterns that are incompatible with Swift 6 strict concurrency and the Swift module system; fixes preserve all intended behavior.

## Issues Encountered

Two Swift 6 strict concurrency/module system errors required fixes before the build succeeded. Both were diagnosed from compiler output and resolved in a single iteration. No architectural changes required.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- heald Swift package compiles cleanly for macOS 15 release target
- ServiceLifecycle dependency resolved and linked — Phase 2 can add Service conformances directly
- OSLog subsystem established (com.heald.daemon) — all future phases use Logger.lifecycle, Logger.core; Phase 2 adds .collector, .analyzer
- LaunchAgent plist template ready for install.sh in a later phase
- No blockers for 01-02 (next plan in Phase 1)

---
*Phase: 01-daemon-foundation*
*Completed: 2026-03-03*
