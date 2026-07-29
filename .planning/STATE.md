---
gsd_state_version: 1.0
milestone: v2.0
milestone_name: product-apple-intelligence
status: complete
last_updated: "2026-07-29"
progress:
  total_phases: 7
  completed_phases: 7
---

# Project State

## Current Position

**Product v2.0.0** — finished local product with Apple Intelligence only.

- Daemon: collectors, storage, cloud push, healing, health checks, maintenance
- AI: `AppleIntelligenceClient` (FoundationModels) — replaces Ollama entirely
- CLI: `heald run` (default), `heald doctor`
- Plan: `docs/superpowers/plans/2026-07-29-heald-product-apple-intelligence.md`

## Decisions (v2)

- AI backend = Apple Intelligence on-device (meisterSiri parity); Ollama removed
- Process kill: AI consult when available; WAIT/IGNORE honor AI; else rules
- Maintenance: no Ollama model pull / LM Studio sync
- Platform floor: macOS 26+ (Package.swift)

## Next (optional ops)

- Publish GitHub release v2.0.0 binary + brew formula sha
- Install on all fleet Macs
- Persist dashboard store beyond serverless memory if fleet empty after cold start
