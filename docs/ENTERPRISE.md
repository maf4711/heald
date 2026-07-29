# heald Enterprise vs Meister (private)

| | **heald Enterprise** | **Meister / meisterSiri (private)** |
|--|----------------------|-------------------------------------|
| Product | Fleet / self-healing daemon | Personal Mac CLI |
| Runtime | Always-on LaunchAgent | On-demand + optional LaunchAgents |
| Dependency | **None on Meister** | Standalone Homebrew formula |
| AI | Apple Intelligence on-device | meisterSiri = Apple; meister = Ollama |
| Scope | Detect → heal continuously | Batch modules when you run them |

## Self-heal loop (heald)

1. Collectors every few seconds (CPU, RAM, disk, thermal, …)
2. Health checks (DNS, Spotlight, security, …)
3. Process healer (sustained high CPU)
4. **SelfHealOrchestrator** (~45s): pressure → native remediation + notify
5. Scheduled maintain: quick 09:15 / deep Sun 10:30

## What else is possible (roadmap)

- Policy packs (corp profile: block USB, enforce FileVault)
- MDM / Jamf webhook on self-heal events
- Multi-Mac fleet dashboard (already heald.sh) with auto-remediation ACK
- SOC-lite: persistence + TCC drift alerts to Slack
- Battery health degradation early warning
- App-crash loop quarantine
- Safe “sudo once” ticket agent for purge / mdutil rebuild
- Compliance reports (ISO/SOC2-style inventory export)
