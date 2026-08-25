# heald — Enterprise self-healing macOS daemon

**Edition:** Enterprise 3.5 · Auto-distribution (client pulls from /api/update)

| Product | Role |
|---------|------|
| **heald** | Always-on self-heal, policy, compliance, fleet |
| **Meister / meisterSiri** | Optional daily batch via `heald meister` / 09:15 bridge (skip if missing) |

## Self-heal

`SelfHealOrchestrator` every ~45s: detect → remediate (if consent=auto) → log → notify → fleet ACK.

Performance autoheal (when load/CPU is high or at boot settle): Spotlight-exclude heavy trees (`~/Library/Developer`, …), strip `RunAtLoad` from interval LaunchAgents, drop Debug login items, SIGTERM runaway `du ~/Documents`. CPU storm (HUD daemon dupes, leaked `it2`, stuck `hooks statusline`) runs **every ~45s even when `consent=log`**. `heald heal` runs the same. Toggle: `performanceAutohealEnabled` in `~/.heald/policy.json`. Hold: `touch ~/.cache/cpu-guard.hold`.

Plus: crash-loop quarantine, battery guardian, network DNS heal, optional safe softwareupdate, Slack webhooks, SIEM syslog, PII redaction.

## Policy / Bank pilot

```bash
heald policy --preset bank
heald policy --auto-update-on     # fleet self-update (default ON)
heald enroll
heald update | update --check
heald compliance
./scripts/publish-client.sh       # ship binary + manifest to all clients
```

`~/.heald/policy.json` · Device: `~/.heald/device.json` · Docs: `docs/AUTO-UPDATE.md`

Env: `HEALD_AUTO_UPDATE=1` · `HEALD_UPDATE_INTERVAL_SEC=1800` · `HEALD_CLOUD=0` · `HEALD_DEVICE_TOKEN`

## Build / install

```bash
swift build -c release
# Bank pilot (recommended):
./scripts/install-bank.sh
./scripts/smoke-test.sh
# Lab:
cp .build/release/heald ~/Library/heald/heald
ln -sfn ~/Library/heald/heald /opt/homebrew/bin/heald
```

## CLI

```bash
heald doctor | status | maintain --profile quick|deep
heald heal | autofix | storage | free
heald policy | enroll | compliance | sudo-setup | update
```

## Docs

- **`docs/ROADMAP.md`** — P0–P3 status (führend)
- `docs/SMOKE-TEST.md` · `docs/P3-EXPAND.md` · `docs/PILOT.md`
- `docs/ELON-CUT-BANK.md` · `docs/THREAT-MODEL.md` · `docs/BANK-ONEPAGER.md`
- Scripts: `install-bank.sh` · `build-pkg.sh` · `smoke-test.sh` · `reviewer-pack.sh` · `trust-status.sh`
