# heald — Enterprise self-healing macOS daemon

**Edition:** Enterprise 3.1 · **No Meister dependency**

| Product | Role |
|---------|------|
| **heald** | Always-on self-heal, policy, compliance, fleet |
| **Meister / meisterSiri** | Private personal CLI only |

## Self-heal

`SelfHealOrchestrator` every ~45s: detect → remediate (if consent=auto) → log → notify → fleet ACK.

Plus: crash-loop quarantine, battery guardian, network DNS heal, optional safe softwareupdate, Slack webhooks.

## Policy

`~/.heald/policy.json` — `heald policy --consent auto|ask|log`

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
heald policy | compliance | sudo-setup [--write]
```

See `docs/ENTERPRISE.md`.
