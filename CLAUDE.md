# heald — Enterprise self-healing macOS daemon

**Edition:** Enterprise 3.2 · **No Meister dependency** · Phase A bank pilot path

| Product | Role |
|---------|------|
| **heald** | Always-on self-heal, policy, compliance, fleet |
| **Meister / meisterSiri** | Private personal CLI only |

## Self-heal

`SelfHealOrchestrator` every ~45s: detect → remediate (if consent=auto) → log → notify → fleet ACK.

Plus: crash-loop quarantine, battery guardian, network DNS heal, optional safe softwareupdate, Slack webhooks, SIEM syslog, PII redaction.

## Policy / Bank pilot

```bash
heald policy --preset bank    # consent=log, cloud off, no kill
heald policy --consent log
heald policy --cloud-off
heald enroll                  # per-device token
heald compliance              # v2 inventory + CIS subset
```

`~/.heald/policy.json` · Device: `~/.heald/device.json`

Env: `HEALD_CLOUD=0` · `HEALD_DEVICE_TOKEN` · `HEALD_SIEM_HOST` · `HEALD_API_KEY` (lab)

## Build / install

```bash
swift build -c release
cp .build/release/heald ~/Library/heald/heald
ln -sfn ~/Library/heald/heald /opt/homebrew/bin/heald
launchctl kickstart -k "gui/$(id -u)/com.heald.daemon"
heald doctor
```

## CLI

```bash
heald doctor | status | maintain --profile quick|deep
heald heal | autofix | storage | free
heald policy | enroll | compliance | sudo-setup | update
```

## Docs

- `docs/ROADMAP-DEUTSCHE-BANK.md`
- `docs/PHASE-A-SPRINT.md`
- `docs/THREAT-MODEL.md`
- `docs/BANK-ONEPAGER.md`
- `docs/ENTERPRISE.md`
