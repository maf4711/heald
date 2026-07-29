# heald — Enterprise self-healing macOS daemon

**Edition:** Enterprise (native). **Not linked to Meister.**

| Product | Role |
|---------|------|
| **heald** | Always-on self-heal + fleet (this repo) |
| **Meister / meisterSiri** | Private personal CLI (`homebrew-meister`) — separate |

## Architecture

- Collectors → MetricsStore (live)
- Health checks (DNS, Spotlight, security, …)
- ProcessHealer (sustained high CPU)
- **SelfHealOrchestrator** (~45s): pressure → native remediate → notify
- MaintenanceService schedules: 09:15 quick · Sun 10:30 deep · 02:00 benchmark

## Build / install (this Mac)

```bash
swift build -c release
mkdir -p ~/Library/heald
cp .build/release/heald ~/Library/heald/heald
ln -sfn ~/Library/heald/heald /opt/homebrew/bin/heald
launchctl kickstart -k "gui/$(id -u)/com.heald.daemon"
heald doctor
```

## CLI

```bash
heald run                 # daemon
heald doctor | status
heald maintain --profile quick|deep
heald heal | autofix | storage | free
```

## Docs

- `docs/ENTERPRISE.md` — product split + roadmap
