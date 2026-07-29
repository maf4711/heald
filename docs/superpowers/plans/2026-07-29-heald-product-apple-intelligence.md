# heald v2 — Fertiges Produkt (Apple Intelligence only)

> **For agentic workers:** Execute task-by-task. Checkboxes track progress.

**Goal:** heald ist ein fertiges, installierbares macOS-Produkt: Daemon heilt, loggt, pusht ans Dashboard; AI läuft **ausschließlich on-device** über Apple Intelligence (FoundationModels), analog zu meisterSiri — **kein Ollama**.

**Architecture:** Swift-Daemon (LaunchAgent) mit Collectors → Storage → Healing → HealthChecks → Maintenance. AI-Backend ist `AppleIntelligenceClient` (`SystemLanguageModel` / `LanguageModelSession`). Bei Unavailable: rule-based Fallback. Cloud-Dashboard bleibt optional (push mit API key).

**Tech Stack:** Swift 6, FoundationModels, ServiceLifecycle, GRDB, ArgumentParser, Next.js dashboard (bestehend)

## Global Constraints

- AI backend: **Apple Intelligence only** (on-device). No Ollama, no cloud LLM, no model pulls.
- Same UX contract as meisterSiri: check availability → prompt → parse structured reply → safety gate on heal commands.
- Daemon must run without AI (rules fallback); AI enhances decisions when available.
- macOS Apple Silicon with Apple Intelligence (host is macOS 26+/27).
- Do not commit secrets; keep existing HEALD_API_KEY install flow.

---

### Task 1: Product plan + AI client

**Files:**
- Create: `Sources/heald/AI/AppleIntelligenceClient.swift`
- Delete or gut: `Sources/heald/AI/OllamaClient.swift`
- Delete or stop using: `Sources/heald/Maintenance/OllamaModelUpdater.swift`

**Produces:**
- `actor AppleIntelligenceClient` with `isAvailable`, `checkAvailability()`, `shouldKillProcess(...)`, `generateDailySummary(...)`, `selfHealAnalyze(...)`, `enum AIDecision`

- [x] **Step 1:** Write plan (this file)
- [x] **Step 2:** Implement `AppleIntelligenceClient` using `FoundationModels`
- [x] **Step 3:** Keep `AIDecision` public/shared

### Task 2: Wire AI everywhere Ollama was

**Files:**
- Modify: `AI/AISafety.swift` (SelfHealingRunner)
- Modify: `AI/NotificationService.swift`
- Modify: `Maintenance/MaintenanceService.swift` (drop Ollama model update + LM Studio)
- Modify: `HealdService.swift`
- Modify: `Healing/HealingService.swift` + `ProcessHealer.swift` (optional AI kill consult)

- [x] Replace `OllamaClient` type with `AppleIntelligenceClient`
- [x] Log "Apple Intelligence" not "Ollama"
- [x] Remove OllamaModels / LMStudioSync maintenance jobs

### Task 3: CLI product surface

**Files:**
- Modify: `HealdApp.swift` — version 2.0.0, subcommands `run` (default) + `doctor`
- Modify: `Package.swift` — platform macOS 26+ if required for FoundationModels

- [x] `heald doctor` prints: daemon binary, AI availability, data dir, API key set?, launchd label
- [x] Version 2.0.0

### Task 4: Docs + install messaging

**Files:**
- Modify: `CLAUDE.md`
- Modify: `.planning/STATE.md` (sync reality)
- Modify: `install.sh` banner if it mentions Ollama (none expected)

- [x] Document Apple Intelligence requirement
- [x] Mark product status shipped-local-AI

### Task 5: Build, install, verify

- [x] `swift build -c release`
- [x] Install binary to `~/Library/heald/heald` + bootstrap LaunchAgent
- [x] `heald doctor` shows AI available
- [x] Process running; optional dashboard machines non-empty

## Definition of Done

1. No Ollama imports/calls in Sources
2. `AppleIntelligenceClient` used for heal analysis + daily summary + optional kill advice
3. Rules work when AI unavailable
4. Daemon installs and stays up via launchd
5. `heald doctor` reports AI status
6. Plan checkboxes complete

## Out of scope (this pass)

- iOS app polish
- API key rotation redesign
- New dashboard features
- Email provider changes
