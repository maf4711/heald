# heald

macOS system health daemon — monitors, diagnoses, and self-heals your Mac.

**v2.2 product:** AI is **Apple Intelligence only** (on-device FoundationModels).  
**Meister integrated:** batch-maintain runs via preferred twin (`meisterSiri` / `meister`).  
heald = continuous observe + schedule; Meister = module suite (heal, autofix, deep clean, …).

## Tech Stack

- Swift 6 / Swift Package Manager (CLI daemon), macOS 26+
- FoundationModels (`SystemLanguageModel` / `LanguageModelSession`) — on-device AI
- swift-service-lifecycle, swift-argument-parser, GRDB
- Next.js dashboard (optional cloud fleet view)
- Native apps: SwiftUI (iOS + macOS) — optional clients

## Key Directories

- `Sources/heald/` — main Swift daemon source
  - `AI/AppleIntelligenceClient.swift` — on-device AI (kill advice, daily summary, self-heal)
  - `AI/AISafety.swift` — command blocklist + SelfHealingRunner
  - `Healing/` — process kill + safelist
  - `HealthChecks/`, `Collectors/`, `Maintenance/`, `Storage/`
- `dashboard/` — Next.js web dashboard
- `launchd/`, `homebrew/`, `install.sh`

## Build and Run

```bash
swift build -c release
.build/release/heald doctor
.build/release/heald status
.build/release/heald maintain --profile quick   # Meister --quick
.build/release/heald maintain --profile deep
.build/release/heald heal | autofix | storage | score | twins-bench | why
.build/release/heald meister <args…>            # passthrough
.build/release/heald run                        # daemon (default)

# Local install (always after build on this Mac):
mkdir -p ~/Library/heald
cp .build/release/heald ~/Library/heald/heald
ln -sfn ~/Library/heald/heald /opt/homebrew/bin/heald
launchctl kickstart -k "gui/$(id -u)/com.heald.daemon"
```

Daemon (Meister installed): 02:00 benchmark · 09:15 `--quick` · Sun 10:30 `--deep`

## AI contract

- Backend: **Apple Intelligence** only
- If unavailable → rule-based healing, no AI self-heal / no AI daily summary
- Heal shell commands always pass `AISafetyBlocklist` before execution
- No model downloads, no localhost:11434

## iOS / iPad client

Universal app in `heald-ios/` (iPhone + iPad, SwiftUI).

```bash
cd heald-ios && xcodegen generate && open Heald.xcodeproj
```

Default API: `https://heald.sh`. See `heald-ios/README.md`.

## Dashboard (Vercel) — always production

- Project: `marco-3586s-projects/heald`
- Git: `maf4711/heald` · production branch **`main`** · root **`dashboard/`**
- Domain: `heald.sh` (and `www.heald.sh`)
- **Always deploy to prod** — never leave a preview as the primary ship path:

```bash
# from repo
./scripts/deploy-dashboard.sh
# or
cd dashboard && npm run deploy
# or
cd dashboard && vercel --prod --yes
```

Push to `main` also triggers a **production** deploy via Vercel Git integration.

## Uninstall

```bash
./uninstall.sh
```
