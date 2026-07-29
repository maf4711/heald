# heald Enterprise 3.1

**Private:** Meister / meisterSiri (`homebrew-meister`) — personal CLI, not a dependency.  
**Enterprise:** heald — always-on self-heal, policy, compliance, fleet.

## Self-heal (background)

Detect → remediate → log → notify (≈45s), policy-gated.

| Signal | Action |
|--------|--------|
| RAM pressure / swap | purge (sudo ticket) |
| Disk free &lt; warn/critical | caches, trash, DerivedData, deep clean |
| Thermal serious/critical | notify + purge |
| Firewall off | enable (if consent=auto) |
| FileVault off | notify + webhook |
| Crash loop | quarantine LaunchAgents |
| Packet loss | DNS flush |
| Battery health/cycles | warn |
| Maintenance window | optional security softwareupdate |

## Policy (`~/.heald/policy.json`)

```bash
heald policy
heald policy --consent auto|ask|log
heald policy --webhook-url 'https://hooks.slack.com/...' --enable-webhook
heald policy --enable-safe-update
```

- **auto** — remediate  
- **ask** — notify only  
- **log** — log only  

## CLI

```bash
heald run | doctor | status
heald maintain --profile quick|deep
heald heal | autofix | storage | free
heald policy | compliance | sudo-setup [--write]
```

## Sudo ticket

```bash
sudo -v
heald sudo-setup --write
# review ~/.heald/sudoers.heald.draft → /etc/sudoers.d/heald
```

## Artifacts

- `~/.heald/data/self_heal.json`
- `~/.heald/data/fleet_ack.ndjson`
- `~/.heald/compliance/compliance-latest.json`
- `~/.heald/policy.json`
