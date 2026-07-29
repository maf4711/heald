# heald

macOS system health daemon — monitors, diagnoses, and self-heals your Mac.

**v2.0 product:** AI is **Apple Intelligence only** (on-device FoundationModels), same model stack as meisterSiri. No Ollama.

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
.build/release/heald doctor   # AI + install health
.build/release/heald run      # daemon (default if no subcommand)

# Install as launchd service (downloads release binary OR use local binary)
./install.sh

# Local install of just-built binary:
mkdir -p ~/Library/heald
cp .build/release/heald ~/Library/heald/heald
# then re-run install.sh steps or bootstrap LaunchAgent with HEALD_API_KEY
```

## AI contract

- Backend: **Apple Intelligence** only
- If unavailable → rule-based healing, no AI self-heal / no AI daily summary
- Heal shell commands always pass `AISafetyBlocklist` before execution
- No model downloads, no localhost:11434

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
