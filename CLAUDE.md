# heald

macOS system health daemon -- monitors, diagnoses, and self-heals your Mac.

## Tech Stack

- Swift 6 / Swift Package Manager (CLI daemon)
- swift-service-lifecycle (graceful start/stop)
- swift-argument-parser (CLI flags)
- GRDB (SQLite storage for metrics/logs)
- Next.js 15 + React 19 + Recharts (web dashboard)
- Native apps: SwiftUI (iOS + macOS)

## Key Directories

- `Sources/heald/` -- main Swift daemon source
  - `main.swift` -- entry point
  - `HealdService.swift` -- service lifecycle
  - `HealthChecks/` -- individual health check modules
  - `Healing/` -- auto-remediation actions
  - `Maintenance/` -- scheduled maintenance tasks
  - `Collectors/` -- system metrics collectors
  - `AI/` -- AI-driven diagnostics
  - `Storage/` -- GRDB database layer
  - `Models/` -- data models
- `dashboard/` -- Next.js web dashboard
- `heald-ios/` -- native iOS app (Xcode + project.yml)
- `heald-macos/` -- native macOS app (Xcode + project.yml)
- `launchd/` -- launchd plist for auto-start
- `homebrew/` -- Homebrew formula

## Build and Run

```bash
# Build the Swift daemon
swift build

# Run
swift run heald

# Install as launchd service
./install.sh

# Dashboard (Next.js)
cd dashboard && bun install && bun dev
```

## Uninstall

```bash
./uninstall.sh
```
