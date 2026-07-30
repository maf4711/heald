# heald for regulated enterprises

**DE / EN one-pager · Pilot-ready narrative**

---

## DE

### Was ist heald?
heald ist ein **macOS Self-Heal- und Compliance-Agent**: beobachtet Systemzustand, erkennt Fehler (RAM, Disk, Crashes, Security-Baselines), greift **nur policy-gesteuert** ein und erzeugt **Audit-Trails** für Fleet/SIEM.

### Was heald **nicht** ist
- Kein Ersatz für EDR (CrowdStrike etc.)
- Kein Ersatz für MDM (Jamf / Intune)
- Kein Cloud-LLM mit Endpoint-Daten (optional **Apple Intelligence on-device**)

### Bank-Pilot Defaults
| Einstellung | Wert |
|-------------|------|
| Consent | `log` (nur protokollieren) |
| Cloud | aus |
| Process Kill | aus |
| PII-Redaction | an |
| Auth | per-Device Token |

```bash
heald policy --preset bank
heald enroll
heald compliance
```

### Daten
- Lokal: `~/.heald/` (Policy, Audit, Metrics)
- Optional: SIEM via Syslog UDP, Fleet HTTPS (EU / später On-Prem)

### Nächste Gates
Notarized pkg · Jamf · SSO Admin · persistente Fleet-DB · DPA/Pen-Test  
→ siehe `docs/ROADMAP-DEUTSCHE-BANK.md`

---

## EN

### What is heald?
heald is a **macOS self-heal and compliance agent**: it observes health signals, detects issues (RAM, disk, crashes, security baselines), remediates **only under policy**, and produces **audit trails** for fleet/SIEM.

### What it is **not**
- Not an EDR replacement  
- Not an MDM replacement  
- No cloud LLM with endpoint data (optional **on-device Apple Intelligence**)

### Bank pilot defaults
`consent=log` · cloud off · no process kill · PII redaction on · per-device tokens.

### Contact path
Architecture review package: threat model, data flow, compliance export v2, sudo least-privilege draft.
