---
phase: 02-metric-collector
plan: 03
subsystem: metrics
tags: [swift, iokit, statfs, diskutil, ps, sendable, servicelifecycle, oslog]

# Dependency graph
requires:
  - phase: 02-metric-collector
    plan: 01
    provides: DiskSnapshot, ProcessSnapshot, MetricsStore actor, Logger.collector
  - phase: 02-metric-collector
    plan: 02
    provides: Collectors directory, withGracefulShutdownHandler pattern (while-true + empty onGracefulShutdown)

provides:
  - DiskCollector Service: disk space via statfs every 60s, I/O via IOKit every 5s, SMART via diskutil every 300s
  - ProcessCollector Service: top-25-by-CPU and top-25-by-RAM lists every 5s via ps subprocess
  - UID-based system process tagging (uid < 500 = isSystem) for Phase 5 safelist

affects:
  - 02-04-PLAN (HealdService wiring — DiskCollector and ProcessCollector ready for ServiceGroup)
  - 05-healer (ProcessCollector.isSystem feeds safelist logic — never kill system-tagged processes)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "IOKit parent traversal with depth limit (max 10) — prevents infinite loop on virtual disk entries in IORegistry"
    - "statfs (not statvfs) for disk space — statvfs returns incorrect f_bsize on macOS (256x too large due to Apple bug)"
    - "Multi-interval polling via cycle counter in a single 5s base loop — avoids multiple concurrent tasks"
    - "ps locale-safe parsing: replace comma with period before Double parsing — German locale outputs commas in ps %CPU column"
    - "while-true + empty onGracefulShutdown — Task.sleep CancellationError breaks loop cleanly (established by CPUCollector/RAMCollector in 02-02)"

key-files:
  created:
    - Sources/heald/Collectors/DiskCollector.swift
    - Sources/heald/Collectors/ProcessCollector.swift
  modified: []

key-decisions:
  - "Multi-interval polling with a single 5s loop and cycle counter — simpler than multiple concurrent Tasks or a Timer; no concurrency overhead"
  - "DiskCollector checks IORegistry for drive existence before diskutil SMART query — avoids spawning processes for non-existent disk slots"
  - "ProcessCollector top-25-by-CPU relies on ps -r sort (kernel-sorted) rather than re-sorting in Swift — reduces allocations"
  - "Locale-safe Double parsing (comma->period) applied to ps output — confirmed issue in German locale from 02-RESEARCH.md"

patterns-established:
  - "while-true + empty onGracefulShutdown closure: all collectors use this pattern; Task.sleep(CancellationError) is the shutdown mechanism"
  - "Subprocess stderr suppressed via Pipe(): keeps OSLog clean, no stderr pollution from diskutil or ps"

requirements-completed: [MON-03, MON-04, MON-05, MON-06, MON-08]

# Metrics
duration: 8min
completed: 2026-03-03
---

# Phase 2 Plan 03: Disk and Process Collectors Summary

**DiskCollector (space/IO/SMART at 3 intervals via statfs+IOKit+diskutil) and ProcessCollector (top-25-by-CPU and top-25-by-RAM via ps with locale-safe parsing) — all 4 metric domains now collected**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-03T06:00:55Z
- **Completed:** 2026-03-03T06:08:55Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- DiskCollector implements three sub-metrics at different polling intervals in one 5s base loop: space (statfs, 60s), I/O (IOKit tick-delta with depth-limited parent traversal, 5s), SMART health (diskutil plist, 300s)
- ProcessCollector runs ps subprocess with locale-safe decimal parsing, produces two independent ranked lists (top-25-by-CPU, top-25-by-RAM), and tags all system processes (uid < 500) with isSystem=true for Phase 5 safelist
- All 4 metric domains (CPU, RAM, Disk, Process) are now fully collected and written to MetricsStore actor

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement DiskCollector** - `511d6ec` (feat — committed as part of 02-02 plan, fix-up commit)
2. **Task 2: Implement ProcessCollector** - `fe0926e` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `Sources/heald/Collectors/DiskCollector.swift` - Service collecting disk space (statfs/60s), I/O throughput (IOKit/5s), SMART health (diskutil plist/300s); IOKit handle leak prevention via IOObjectRelease; depth-limited parent traversal
- `Sources/heald/Collectors/ProcessCollector.swift` - Service running ps -Aceo subprocess every 5s; locale-safe comma-to-dot CPU parsing; top-25 by CPU (ps pre-sorted) and top-25 by RAM (Swift sort); isSystem = uid < 500

## Decisions Made

- Multi-interval polling in a single 5s loop with cycle counter: avoids spawning extra Tasks or Timers; DiskCollector increments cycle each iteration and gates sub-collectors on modulo arithmetic
- IORegistry existence check before diskutil SMART query: prevents up to 9 wasted subprocess spawns per cycle on machines with fewer physical disks
- ps -r flag for pre-sorted CPU output: kernel already sorts, no need to duplicate in Swift; only byRAM needs a Swift sort

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed `Darwin.statfs()` naming conflict — struct vs function ambiguity**
- **Found during:** Task 1 (DiskCollector implementation)
- **Issue:** `Darwin.statfs(path, &stat)` caused compile error: "argument passed to call that takes no arguments" because `Darwin.statfs` resolved to the struct type, not the function
- **Fix:** Changed to `url.path.withCString({ statfs($0, &stat) == 0 })` — uses the C function directly via CString bridge
- **Files modified:** Sources/heald/Collectors/DiskCollector.swift
- **Verification:** swift build passes
- **Committed in:** 511d6ec

**2. [Rule 1 - Bug] Fixed `repeat...while !shutdown` pattern — naming conflict with Darwin `shutdown()` socket function**
- **Found during:** Task 1 (DiskCollector implementation)
- **Issue:** Variable named `shutdown` conflicted with Darwin's `shutdown(Int32, Int32) -> Int32` socket function; also `repeat...while` inside async context had Swift 6 concurrency issues with mutation from concurrent closure
- **Fix:** Adopted `while true` + empty `onGracefulShutdown` closure (same pattern as CPUCollector/RAMCollector from 02-02) — Task.sleep CancellationError breaks the loop on shutdown
- **Files modified:** Sources/heald/Collectors/DiskCollector.swift
- **Verification:** swift build passes, no warnings
- **Committed in:** 511d6ec

---

**Total deviations:** 2 auto-fixed (both Rule 1 - Bug)
**Impact on plan:** Both fixes were compile-blocking. The while-true pattern is now the established standard for all collectors. No scope creep.

## Issues Encountered

- DiskCollector.swift was committed as part of the 02-02 plan (commit 511d6ec included both RAMCollector.swift and DiskCollector.swift as a combined fix-up). The 02-03 Task 1 commit therefore points to 511d6ec rather than a fresh commit. ProcessCollector.swift was committed fresh as fe0926e.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 4 metric collectors (CPU, RAM, Disk, Process) are implemented and compile clean
- All collectors conform to Service and use withGracefulShutdownHandler
- Next plan (02-04) should wire all 4 collectors into HealdService via ServiceGroup
- No blockers

## Self-Check: PASSED

- FOUND: Sources/heald/Collectors/DiskCollector.swift
- FOUND: Sources/heald/Collectors/ProcessCollector.swift
- FOUND commit: 511d6ec (feat(02-02): implement RAMCollector + DiskCollector fix-up)
- FOUND commit: fe0926e (feat(02-03): implement ProcessCollector with CPU/RAM ranking)
- swift build: Build complete! (0.12s)

---
*Phase: 02-metric-collector*
*Completed: 2026-03-03*
