---
phase: 02-metric-collector
plan: 02
subsystem: metrics
tags: [swift, mach, darwin, cpu, ram, service-lifecycle, oslog, swift6]

# Dependency graph
requires:
  - phase: 02-metric-collector
    plan: 01
    provides: CPUSnapshot, RAMSnapshot, MetricsStore actor, Logger.collector

provides:
  - CPUCollector Service: tick-delta CPU sampling via host_processor_info with vm_deallocate
  - RAMCollector Service: RAM breakdown via host_statistics64 + swap spike detection
  - Swap spike logging at .warning level with suspect process name

affects:
  - HealdService.swift (Phase 2 wiring plan will register both collectors)
  - 02-03-PLAN (DiskCollector, same Service pattern)
  - 02-05-PLAN (ProcessCollector, same Service pattern)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "while true + withGracefulShutdownHandler pattern: Task.sleep throws CancellationError on shutdown, breaking the loop — no mutable shutdown flag in @Sendable closure"
    - "Tick-delta CPU sampling: host_processor_info PROCESSOR_CPU_LOAD_INFO with vm_deallocate on previous buffer each cycle"
    - "First-sample discard: first CPU sample sets baseline only, publishes .zero — prevents 100%/0% startup spike"
    - "Activity Monitor 'used' RAM formula: active+inactive+speculative+wired+compressed-purgeable-external"
    - "sysconf(_SC_PAGESIZE) instead of vm_page_size — vm_page_size is mutable shared state rejected by Swift 6 strict concurrency"
    - "Mach pointers stay local to run() — never cross actor boundary, satisfying Swift 6 Sendable requirements"

key-files:
  created:
    - Sources/heald/Collectors/CPUCollector.swift
    - Sources/heald/Collectors/RAMCollector.swift
    - Sources/heald/Collectors/DiskCollector.swift
  modified: []

key-decisions:
  - "while true + CancellationError pattern for shutdown instead of mutable shutdown flag — Swift 6 rejects mutating captured vars in @Sendable onGracefulShutdown closure"
  - "sysconf(_SC_PAGESIZE) for page size in RAMCollector — vm_page_size is a mutable C global, Swift 6 strict concurrency rejects it as shared mutable state"
  - "Final prevCpuInfo buffer not freed on shutdown path — acceptable because OS reclaims all process memory on exit; avoids @Sendable closure capture complexity"

patterns-established:
  - "Service loop pattern: while true { collect; update store; try await Task.sleep(for: .seconds(5)) } inside withGracefulShutdownHandler — consistent across all 5 collectors"

requirements-completed: [MON-01, MON-02, MON-07]

# Metrics
duration: 5min
completed: 2026-03-03
---

# Phase 2 Plan 02: CPU and RAM Collectors Summary

**CPUCollector (tick-delta via host_processor_info with vm_deallocate) and RAMCollector (host_statistics64 + sysctlbyname swap/pressure + swap spike detection) as Swift 6-compliant Service implementations**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-03T06:00:47Z
- **Completed:** 2026-03-03T06:05:47Z
- **Tasks:** 2
- **Files modified:** 3 (2 new + DiskCollector pre-existing fix)

## Accomplishments

- CPUCollector: per-core tick-delta sampling via host_processor_info; vm_deallocate on previous buffer each cycle; first sample discards to avoid startup spike; overall = average of per-core values (matching Activity Monitor)
- RAMCollector: Activity Monitor 'used' formula from host_statistics64 page counts; swap from sysctlbyname("vm.swapusage"); pressure from sysctlbyname("kern.memorystatus_vm_pressure_level"); calls detectSwapSpike after each updateRAM, logs spike at .warning with suspect process name
- Both use the `while true + withGracefulShutdownHandler` pattern — no mutable captured vars in @Sendable closures, Swift 6 compliant

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement CPUCollector with tick-delta sampling** - `8421398` (feat)
2. **Task 2: Implement RAMCollector with swap spike detection** - `511d6ec` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `Sources/heald/Collectors/CPUCollector.swift` - CPU tick-delta collector; host_processor_info; vm_deallocate; first-sample discard; while true loop
- `Sources/heald/Collectors/RAMCollector.swift` - RAM breakdown via host_statistics64; swap/pressure via sysctlbyname; swap spike detection and logging
- `Sources/heald/Collectors/DiskCollector.swift` - Pre-existing file with build-blocking bugs (statfs call syntax, shutdown flag in @Sendable closure); fixed as deviation Rule 3

## Decisions Made

- `while true` with `CancellationError` from `Task.sleep` for shutdown — Swift 6 rejects mutating a `var` captured by a `@Sendable` `onGracefulShutdown` closure (which runs on a different thread). The previous `repeat { ... } while !shutdown` pattern with `shutdown = true` in the closure is rejected by the compiler.
- `sysconf(_SC_PAGESIZE)` instead of `vm_page_size` — the Darwin global `vm_page_size` is `extern vm_size_t`, a mutable C global; Swift 6 strict concurrency treats it as shared mutable state and rejects access outside a synchronization context.
- Final `prevCpuInfo` buffer is intentionally not freed in the `onGracefulShutdown` closure — freeing it there would require capturing the mutable `prevCpuInfo` var in a `@Sendable` context (rejected). The OS reclaims all process memory on exit, so this is a benign accept.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed pre-existing DiskCollector.swift build errors**
- **Found during:** Task 2 (RAMCollector build verification)
- **Issue:** DiskCollector.swift already existed in the Collectors directory with two Swift 6 errors: (a) `Darwin.statfs(url.path, &stat)` used wrong syntax (treats `statfs` as initializer), (b) `shutdown = true` in `@Sendable onGracefulShutdown` closure was rejected as mutation of captured var
- **Fix:** Changed `Darwin.statfs()` initializer to `var stat = statfs()` + `url.path.withCString({ statfs($0, &stat) == 0 })`; replaced `repeat/while !shutdown` + `shutdown = true` with `while true` + empty `onGracefulShutdown` (CancellationError from Task.sleep exits the loop)
- **Files modified:** Sources/heald/Collectors/DiskCollector.swift
- **Verification:** swift build exits 0 with no errors or warnings
- **Committed in:** 511d6ec (Task 2 commit)

**2. [Rule 1 - Bug] Fixed vm_page_size Swift 6 concurrency violation in RAMCollector**
- **Found during:** Task 2 build
- **Issue:** `Double(vm_page_size)` triggers "reference to var 'vm_page_size' is not concurrency-safe because it involves shared mutable state"
- **Fix:** Replaced with `Double(sysconf(_SC_PAGESIZE))`
- **Files modified:** Sources/heald/Collectors/RAMCollector.swift
- **Verification:** swift build exits 0
- **Committed in:** 511d6ec (Task 2 commit)

**3. [Rule 1 - Bug] Fixed CPUCollector onGracefulShutdown SendableClosureCaptures error**
- **Found during:** Task 1 first build attempt
- **Issue:** Attempting to call `vm_deallocate` on `prevCpuInfo` in `onGracefulShutdown` closure captured mutable vars in a `@Sendable` context
- **Fix:** Moved `vm_deallocate` call to after the `withGracefulShutdownHandler` block (non-Sendable context); left onGracefulShutdown empty since Task.sleep cancellation handles loop exit
- **Files modified:** Sources/heald/Collectors/CPUCollector.swift
- **Verification:** swift build exits 0
- **Committed in:** 8421398 (Task 1 commit)

---

**Total deviations:** 3 auto-fixed (2 Rule 1 bugs, 1 Rule 3 blocking)
**Impact on plan:** All fixes required for Swift 6 strict concurrency compliance. No scope creep. The `while true + CancellationError` pattern established here must be used in all remaining Phase 2 collectors.

## Issues Encountered

- Swift 6 strict concurrency is more restrictive than Swift 5 regarding mutable vars captured in `@Sendable` closures and mutable C globals. The `onGracefulShutdown` closure is `@Sendable`, so mutating any `var` captured from the enclosing scope is rejected. This pattern affects all collectors and was resolved once in CPUCollector then applied consistently.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CPUCollector and RAMCollector are complete Service implementations ready to be wired into HealdService
- DiskCollector.swift exists in Collectors/ with correct Swift 6 patterns — Plan 02-03 can build directly on it
- The `while true + withGracefulShutdownHandler` Service loop pattern is established and verified
- No blockers for 02-03 (DiskCollector) or 02-04 (ProcessCollector)

## Self-Check: PASSED

- FOUND: Sources/heald/Collectors/CPUCollector.swift
- FOUND: Sources/heald/Collectors/RAMCollector.swift
- FOUND: Sources/heald/Collectors/DiskCollector.swift
- FOUND commit: 8421398 (feat(02-02): implement CPUCollector with tick-delta sampling)
- FOUND commit: 511d6ec (feat(02-02): implement RAMCollector with swap spike detection)
- swift build: PASSED (Build complete)

---
*Phase: 02-metric-collector*
*Completed: 2026-03-03*
