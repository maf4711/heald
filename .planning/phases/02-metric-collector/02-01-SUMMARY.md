---
phase: 02-metric-collector
plan: 01
subsystem: metrics
tags: [swift, actor, sendable, mach, metrics, oslog]

# Dependency graph
requires:
  - phase: 01-daemon-foundation
    provides: HealdService.swift, Logging.swift, ServiceLifecycle infrastructure

provides:
  - CPUSnapshot Sendable value type (overall + per-core fractions)
  - RAMSnapshot Sendable value type (used/wired/active/compressed/swap/pressure)
  - DiskSnapshot with VolumeSpaceInfo, DiskIODelta, DiskIOCounters, SMARTInfo
  - ProcessSnapshot with ProcessEntry ranked lists (byCPU, byRAM)
  - MetricsStore actor — single source of truth for all metric state
  - SwapSpike type with dual-threshold detection (50MB delta + pressure>=2)
  - Logger.collector OSLog category

affects:
  - 02-02-PLAN (CPUCollector implements against CPUSnapshot/MetricsStore)
  - 02-03-PLAN (RAMCollector implements against RAMSnapshot/MetricsStore)
  - 02-04-PLAN (DiskCollector implements against DiskSnapshot/MetricsStore)
  - 02-05-PLAN (ProcessCollector implements against ProcessSnapshot/MetricsStore)
  - 03-storage (reads from MetricsStore)
  - 04-cloud (reads from MetricsStore)
  - 05-healer (uses ProcessEntry.isSystem safelist flag)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Sendable struct model types — all metric snapshots are value types with let properties and no imported frameworks beyond Foundation"
    - "Actor-isolated metrics state — MetricsStore actor serializes all concurrent reads/writes; Swift 6 strict concurrency validated at compile time"
    - "Dual-threshold swap spike detection — both rate-of-change (>50MB/interval) AND pressure>=2 required to avoid Apple Silicon false positives"

key-files:
  created:
    - Sources/heald/Models/CPUSnapshot.swift
    - Sources/heald/Models/RAMSnapshot.swift
    - Sources/heald/Models/DiskSnapshot.swift
    - Sources/heald/Models/ProcessSnapshot.swift
    - Sources/heald/MetricsStore.swift
  modified:
    - Sources/heald/Logging.swift

key-decisions:
  - "ProcessEntry.isSystem uses uid < 500 threshold — feeds Phase 5 safelist: system-tagged processes are never killed"
  - "SwapSpike detection requires BOTH >50MB delta AND pressureLevel>=2 — prevents Apple Silicon false positives from normal aggressive swap behavior"
  - "DiskIOCounters type kept separate from DiskIODelta — counters are cumulative (for delta math), deltas are the published metric"
  - "All models import Foundation only — no OSLog/IOKit/Darwin in model files keeps them portable and testable"

patterns-established:
  - "Model-first ordering: data contracts defined before collectors — prevents scavenger hunt anti-pattern in subsequent plans"
  - "Static .zero/.empty initializers on all snapshot types — safe default state for MetricsStore before first collection cycle"

requirements-completed: [MON-01, MON-02, MON-03, MON-04, MON-05, MON-07, MON-08]

# Metrics
duration: 1min
completed: 2026-03-03
---

# Phase 2 Plan 01: Metric Data Contracts Summary

**6 Sendable value types + MetricsStore actor defining all metric data contracts for Phase 2 collectors — interface-first ordering against Swift 6 strict concurrency**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-03T07:36:38Z
- **Completed:** 2026-03-03T07:37:38Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Four Sendable metric snapshot types (CPU, RAM, Disk, Process) with static zero/empty initializers — every subsequent collector has a typed contract to implement against
- MetricsStore Swift 6 actor with typed update methods for all 4 domains and dual-threshold swap spike detection (MON-07)
- Logger.collector OSLog category activated for all collector logging in subsequent plans

## Task Commits

Each task was committed atomically:

1. **Task 1: Create all metric snapshot model types** - `1d6279f` (feat)
2. **Task 2: Create MetricsStore actor and update Logging.swift** - `7c61a51` (feat)

**Plan metadata:** (docs commit below)

## Files Created/Modified

- `Sources/heald/Models/CPUSnapshot.swift` - overall + perCore fractions, timestamp, static .zero
- `Sources/heald/Models/RAMSnapshot.swift` - used/wired/active/compressed/swap/pressureLevel, static .zero
- `Sources/heald/Models/DiskSnapshot.swift` - VolumeSpaceInfo, DiskIODelta, DiskIOCounters, SMARTInfo, DiskSnapshot with static .empty
- `Sources/heald/Models/ProcessSnapshot.swift` - ProcessEntry (pid/name/cpu/ram/uid/isSystem), ProcessSnapshot byCPU+byRAM, static .empty
- `Sources/heald/MetricsStore.swift` - actor with 4 update methods + detectSwapSpike + SwapSpike type
- `Sources/heald/Logging.swift` - added static .collector category, removed Phase 2 TODO comment

## Decisions Made

- ProcessEntry.isSystem uses uid < 500 — aligns with research recommendation and feeds Phase 5 safelist logic; system-tagged processes are never killed
- SwapSpike dual-threshold (>50MB delta AND pressure>=2) — research confirmed Apple Silicon aggressively swaps under normal conditions; single threshold would fire constantly
- DiskIOCounters kept as separate type from DiskIODelta — cumulative counters are internal implementation detail for delta math; only deltas are published as metrics
- Models import Foundation only — keeps model files testable in isolation without macOS-specific framework dependencies

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All data contracts defined — CPUCollector, RAMCollector, DiskCollector, ProcessCollector in subsequent plans each have a typed snapshot struct and MetricsStore update method ready
- Logger.collector category available for all Phase 2 collector logging
- SwapSpike detection wired — RAMCollector (plan 02-03) calls detectSwapSpike after each updateRAM call
- No blockers for 02-02 through 02-05

---
*Phase: 02-metric-collector*
*Completed: 2026-03-03*
