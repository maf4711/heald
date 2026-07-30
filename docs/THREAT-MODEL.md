# heald Threat Model (Phase A)

**Audience:** Security Architecture Review (bank pilot)  
**Version:** 3.2.0 · 2026-07-30

## 1. Assets

| Asset | Sensitivity |
|-------|-------------|
| Endpoint metrics (CPU/RAM/disk) | Low–Medium |
| Process names / PIDs | Medium (may reveal tools) |
| Activity log (heals, crashes) | Medium |
| Device token (`~/.heald/device.json`) | **High** (auth) |
| Policy file | Medium |
| Local metrics.db | Medium |
| Apple Intelligence prompts (on-device) | Stays on device |

## 2. Trust boundaries

```
[User/Mac] --local--> [heald daemon]
     |                      |
     |                      +--> local disk (~/.heald)
     |                      +--> optional UDP syslog (SIEM)
     |                      +--> optional HTTPS heald.sh (fleet)
     v
[MDM / admin] --pkg/profile--> install + policy seed
```

## 3. Data leaving the Mac

| Channel | Data | Control |
|---------|------|---------|
| Cloud ingest | metrics + activity events | `cloudEnabled` / `HEALD_CLOUD=0` |
| SIEM syslog | redacted activity lines | `siemSyslog*` / `HEALD_SIEM_HOST` |
| Slack webhook | optional notifications | policy |
| Apple Intelligence | none off-device | on-device only |

**Default bank preset:** cloud **off**, remediation **log-only**, PII redaction **on**.

## 4. Attack surface

| Vector | Risk | Mitigation |
|--------|------|------------|
| Shared fleet API key | Token theft = fleet write | Device tokens; rotate; no shared key in bank |
| Malicious update binary | RCE as user | Notarization + SHA-256 (Phase A script); signed policy later |
| Local policy tamper | Weaken consent | MDM profile overwrite (Phase C); file perms |
| Log injection to SIEM | Noise / spoof | Host-only UDP; mTLS later |
| Privilege escalation via sudoers | Broad sudo | Draft least-privilege sudoers only |
| PII in crash paths | GDPR | `PIIRedactor` on outbound |

## 5. Abuse cases

1. Attacker with user access disables heald → **detect via fleet lastSeen**  
2. Attacker enables `consent=auto` + kill → **bank preset disables kill; MDM re-push policy**  
3. Stolen device token → **server revoke list (Phase B)**  
4. Supply-chain malicious brew formula → **prefer notarized pkg from internal repo**

## 6. Residual risks (accepted for pilot)

- Vercel serverless store durability (lab only; bank uses no-cloud or EU DB in B)  
- UDP syslog unauthenticated  
- Notarization requires org Apple Developer account  

## 7. Review checklist

- [ ] Data-flow approved  
- [ ] Bank preset is default for pilot group  
- [ ] No shared production API key  
- [ ] Full Disk Access / DiagnosticReports justified  
- [ ] Incident: `heald policy --consent log --cloud-off` documented  
