---
phase: 01-daemon-foundation
plan: "02"
subsystem: infra
tags: [bash, launchd, launchctl, homebrew, swift, install-script]

requires:
  - phase: 01-daemon-foundation plan 01
    provides: heald Swift package, LaunchAgent plist template at heald/launchd/com.heald.daemon.plist

provides:
  - install.sh: one-step deployment (brew, ollama, swift build, plist substitution, launchctl bootstrap)
  - uninstall.sh: full removal (launchctl bootout, plist rm, ~/Library/heald/ rm -rf)

affects:
  - 01-daemon-foundation (phase complete after this)
  - 04-cloud-api (install.sh is the foundation for one-liner install command)

tech-stack:
  added: [bash, launchctl bootstrap/bootout, plutil, sed USERNAME substitution]
  patterns:
    - launchctl bootstrap/bootout (Sequoia-compatible, not deprecated load/unload)
    - sed USERNAME placeholder substitution for per-user plist installation
    - plutil -lint validation before launchctl bootstrap (catch XML errors early)
    - bootout-before-bootstrap pattern for idempotent re-install
    - Root guard (EUID check) at top of install script

key-files:
  created:
    - heald/install.sh
    - heald/uninstall.sh
  modified: []

key-decisions:
  - "plutil -lint runs before launchctl bootstrap to catch plist XML errors before silent launchd failure"
  - "uninstall.sh intentionally does not remove ollama — it may be used independently; comment explains this"
  - "bootout before bootstrap in install.sh makes re-install safe without checking load state first"

patterns-established:
  - "launchctl bootstrap gui/$(id -u) $PLIST — Sequoia-compatible load pattern"
  - "launchctl bootout gui/$(id -u)/${LABEL} 2>/dev/null || true — idempotent unload"
  - "sed s|USERNAME|$(whoami)|g for plist USERNAME placeholder substitution"

requirements-completed: [DAEM-04, DAEM-05]

duration: 3min
completed: 2026-03-03
---

# Phase 1 Plan 02: Install and Uninstall Scripts Summary

**install.sh + uninstall.sh delivering end-to-end heald lifecycle management: Homebrew/ollama detection, swift build -c release, sed USERNAME plist substitution, plutil-lint validation, and Sequoia-compatible launchctl bootstrap/bootout**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-03T04:37:34Z
- **Completed:** 2026-03-03T04:40:30Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- install.sh: single command deploys heald from source to running LaunchAgent on any Mac
- uninstall.sh: single command fully removes heald with no leftover files
- Both scripts use Sequoia-correct launchctl commands (bootstrap/bootout, not deprecated load/unload)

## Task Commits

Each task was committed atomically:

1. **Task 1: Write install.sh** - `dc55e42` (feat)
2. **Task 2: Write uninstall.sh** - `0e3fa25` (feat)

## Files Created/Modified

- `heald/install.sh` - One-step install: brew, ollama, swift build, plist deploy, launchctl bootstrap
- `heald/uninstall.sh` - Full removal: launchctl bootout, plist rm, ~/Library/heald/ rm -rf

## Decisions Made

- plutil -lint runs before launchctl bootstrap to surface plist XML errors early (silent launchd failure is hard to debug)
- uninstall.sh does not remove ollama — user may have installed it independently; comment explains removal command if needed
- bootout-before-bootstrap pattern in install.sh makes re-install idempotent without any conditional state check

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Phase 1 complete: Swift daemon skeleton, LaunchAgent plist template, install/uninstall scripts all committed
- install.sh is the foundation for the Phase 4 one-liner install command (curl | bash)
- No blockers for subsequent phases

---
*Phase: 01-daemon-foundation*
*Completed: 2026-03-03*
