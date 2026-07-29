---
gsd_state_version: 1.0
milestone: v3.0
milestone_name: enterprise-auto-update
status: complete
last_updated: "2026-07-29"
---

# Project State

## Current Position

**Product v3.0.0** — enterprise self-heal + auto-update + heald.sh fleet dashboard.

### Live

| Piece | Status |
|-------|--------|
| Daemon | collectors, storage, heal, health, maintenance, AI (Apple Intelligence) |
| Auto-update | `AutoUpdateService` + `GET /api/update` + `heald update` |
| Release | GitHub `v3.0.0` binary + Homebrew formula |
| Dashboard | https://heald.sh (always prod deploys) |
| iOS | Universal client + TestFlight build 1 |
| Store listing | de-DE metadata filled (screenshots still manual) |

### Next (ops / polish)

1. App Store **screenshots** for iPhone 6.5" / iPad
2. Optional: create new ASC app under `com.heald.app` (current ASC ID is immutable `com.merados.heald.app`)
3. Optional: enable **Vercel Blob** (`BLOB_READ_WRITE_TOKEN`) for fleet store across all serverless instances
4. Fleet install on all Macs via `install.sh` / `heald update`

## Decisions

- AI = Apple Intelligence on-device only
- Primary domain = heald.sh
- Managed binary path = `~/Library/heald/heald` (required for auto-update)
- Dashboard store = globalThis + /tmp + optional Blob
