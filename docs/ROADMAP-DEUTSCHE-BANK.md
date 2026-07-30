# heald Roadmap — „Deutsche Bank ready“

**Stand:** 2026-07-30 · heald Enterprise ~3.1  
**Ziel:** heald als genehmigungsfähiges macOS Self-Heal / Fleet-Health Produkt in einer deutschen Großbank (DB / Konzern-IT / BaFin-relevant).

> **Realität:** Kein Consumer-Daemon „besteht“ bei DB nur mit coolen Features.  
> Bank = **Security Review + Vendor Assessment + DORA + Betriebsmodell + Support + On-Prem**.  
> Self-Heal ist der *Nutzen*; Audit, Kontrolle und Lieferkette sind der *Pass*.

---

## 0. Was heald heute schon mitbringt (Basis)

| Bereich | Status | Hinweis |
|---------|--------|---------|
| Always-on Self-Heal (detect → fix → log) | ✅ | Policy-gated (`auto` / `ask` / `log`) |
| Security Checks (FileVault, Firewall, SIP, Gatekeeper, XProtect) | ✅ | oft Warn, selten erzwingen |
| Activity-Log + Cloud-Push Events | ✅ | Cursor-Push; Dashboard ephemeral |
| Compliance JSON Export | ⚠️ | Snapshot, kein Audit-Pack |
| Policy Pack + Webhooks | ⚠️ | lokal JSON, kein zentrales MDM |
| Sudo ticket / least privilege path | ⚠️ | manuell, kein IdM |
| Auto-Update vom Server | ⚠️ | GitHub binary, kein signed enterprise channel |
| On-device AI (Apple Intelligence) | ✅ | starkes Argument: keine Cloud-LLM-Daten |
| Fleet Dashboard (heald.sh) | ⚠️ | Serverless, nicht bankentauglich persistent |
| Code Signing / Notarization | ❌ | adhoc / unsigned |
| MDM / Jamf / Intune | ❌ | |
| SIEM / Splunk / Sentinel | ❌ | |
| On-Prem / Private Cloud | ❌ | |
| DPA, SBOM, Pen-Test, SOC2 | ❌ | commercial / process |

**Gap-Score (grob):** Product Core ~40% · Bank-Gate ~10%.

---

## 1. Bank-Gate: Was „bestehen“ wirklich heißt

Deutsche Bank / Konzern-IT prüft typischerweise in Wellen:

1. **Security Architecture Review** (Threat Model, Data Flow, Privileges)
2. **Vendor / Third-Party Risk** (DPA, Subprocessors, Exit, Insurance)
3. **DORA / ICT Risk** (ICT third party, resilience, logging, incident)
4. **Endpoint / Mac Engineering** (Jamf, CIS macOS, TCC, signing)
5. **Data Protection** (GDPR Art. 28, EU residency, no US-only SaaS ohne Vertrag)
6. **Change & Ops** (CAB, rollback, support hours, RACI)
7. **Pilot** (1 Team → 50 Macs → BU)

Ohne (1)–(4) kommt man nicht in (7).  
Self-Heal allein ist **kein** Gate — es ist der Business Case *nach* den Gates.

---

## 2. Roadmap-Phasen

### Phase A — **Bank Pilot Ready** (6–10 Wochen)  
*Ziel: interner Pilot bei 20–50 Macs einer DB-nahen / Konzern-IT-Umgebung ohne Prod-Kritikalität.*

| # | Deliverable | Warum Bank | Aufwand |
|---|-------------|------------|---------|
| A1 | **Apple Developer ID + Notarization** des Binaries | Gatekeeper, kein „untrusted developer“ | M |
| A2 | **Pkg + signed LaunchAgent** Installer (kein raw curl\|bash als Prod-Pfad) | Change-Prozess, Reproduzierbarkeit | M |
| A3 | **SBOM** (Syft/CycloneDX) + Dependency pin in CI | Supply-chain / DORA | S |
| A4 | **Threat Model** (1 Seite Data-Flow: was verlässt den Mac?) | Security Review | S |
| A5 | **Default Policy „bank“**: `consent=log` oder `ask`, self-heal opt-in, kein process kill default | Zero surprise | S |
| A6 | **Immutable local audit**: append-only activity + hash-chain optional | Audit trail | M |
| A7 | **Compliance Export v2**: CIS-ish checks, serial, user, last login, FileVault, MDM enrollment status | Asset/Audit | M |
| A8 | **Kill-switch / Safe mode**: `heald policy --consent log` remote + local file | Incident response | S |
| A9 | **No-cloud mode**: `HEALD_CLOUD=0` — alles lokal, Export nur USB/share | Data residency Pilot | S |
| A10 | **Privacy manifest**: was sammelt heald (Prozesse, Hostnamen, Pfade)? Allowlist | DSGVO | S |

**Exit-Kriterium A:** Security kann „limited pilot“ abnicken; Binary notarized; default ist non-destructive.

---

### Phase B — **Enterprise Control Plane** (8–14 Wochen)  
*Ziel: zentrale Steuerung wie ein Endpoint-Agent, nicht wie ein Hobby-Daemon.*

| # | Deliverable | Warum Bank | Aufwand |
|---|-------------|------------|---------|
| B1 | **Persistent Fleet Backend** (Postgres/Turso EU, nicht nur Vercel memory) | Audit + 10k machines | L |
| B2 | **Org / Tenant / Site** Modell (Bank → BU → Team → Mac) | IAM / Fleet | M |
| B3 | **Device identity**: hardware UUID + enrollment token (kein shared API key `REDACTED`) | Shared secret = Disqualifikation | M |
| B4 | **Signed policy push** vom Server (ed25519), Client verifiziert | Remote config ohne MITM | M |
| B5 | **Remote actions mit Approval**: quarantine, update, deep clean — 4-eyes optional | Change control | L |
| B6 | **Role-based access** (Viewer / Operator / Admin) + SSO (Entra ID / Okta OIDC) | Bank IAM | L |
| B7 | **SIEM export**: syslog / HTTPS CEF / Splunk HEC / MS Sentinel | SOC | M |
| B8 | **Webhook → ServiceNow / Jira** Incident tickets | Ops workflow | M |
| B9 | **Update channel**: `stable` / `pilot` / `blocked`, staged rollout % | Change freeze | M |
| B10 | **Dashboard EU-only** + Admin Audit Log (who changed policy) | DORA / revision | M |

**Exit-Kriterium B:** Fleet mit per-device auth, SSO Admin, SIEM, policy remote, kein shared key.

---

### Phase C — **MDM & Platform Fit** (6–10 Wochen, parallel B)  
*Ziel: „gehört zur Mac-Plattform“, nicht „Schatten-IT“.*

| # | Deliverable | Warum Bank | Aufwand |
|---|-------------|------------|---------|
| C1 | **Jamf Pro** Custom App / Policy JSON via Configuration Profile | Standard DB-ish Mac path | M |
| C2 | **Microsoft Intune** (falls Hybrid) | Konzern-Windows+Mac | M |
| C3 | **Managed Preferences** domain `sh.heald` (consent, cloud URL, features) | No user-writable policy only | M |
| C4 | **TCC / Full Disk Access** documented + PPPC profile sample | Crash logs, DiagnosticReports | S |
| C5 | **Privileged Helper / SMAppService** statt breitem sudoers | Least privilege | L |
| C6 | **CIS macOS Benchmark mapping** (report only → enforce later) | Security baseline | M |
| C7 | **FileVault / Firewall enforce** via policy + ticket to IT if fail | Compliance, not only warn | M |
| C8 | **Network egress allowlist** docs (only `ingest.heald.eu` etc.) | Firewall tickets | S |

**Exit-Kriterium C:** Install über Jamf; Policy via Profile; Helper ohne passwordless full sudo.

---

### Phase D — **Regulated Ops & Commercial** (parallel, 3–6 Monate)  
*Ziel: Vendor Assessment besteht.*

| # | Deliverable | Owner |
|---|-------------|--------|
| D1 | **AVV / DPA** (DE/EN), Subprocessor list, EU hosting option | Legal |
| D2 | **ISMS light**: access control, backup, incident runbook, vuln disclosure | Sec |
| D3 | **Pen-Test** (extern) + Findings closed | Sec |
| D4 | **SOC 2 Type I** (später Type II) oder ISO 27001 path | GRC |
| D5 | **DORA ICT third-party pack**: RTO/RPO, exit plan, support matrix | Ops |
| D6 | **SLA**: 8×5 / 24×7, DE Sprach-Support, Escalation | Sales/Ops |
| D7 | **Insurance** (cyber / E&O) | Finance |
| D8 | **Pricing**: seat-based + on-prem appliance option | Sales |
| D9 | **On-Prem / Private VPC** Deploy (Helm oder single VM) | Eng |
| D10 | **Reference architecture** PDF für Architekten | Eng |

**Exit-Kriterium D:** Due-Diligence-Paket (ZIP) in 48h lieferbar.

---

### Phase E — **Bank-Grade Self-Heal** (Features, nach A–C)  
*Erst hier Self-Heal „aggressiv“ freischalten.*

| # | Feature | Bank-tauglich nur wenn… |
|---|---------|-------------------------|
| E1 | Process kill | Allowlist aus Jamf + never system critical; dual control for VIP hosts |
| E2 | Crash-loop quarantine | Report to SOC; optional auto for non-managed agents only |
| E3 | Disk cleanup | Never touch `Documents`, only known caches; dry-run report first |
| E4 | Network self-heal | DNS flush ok; VPN/proxy never touch without profile |
| E5 | Softwareupdate | Only Apple security updates in maintenance window; CAB flag |
| E6 | Log/fault scanner | PII redaction in paths/usernames before cloud |
| E7 | AI self-heal | **On-device only** forever for bank tier; no command without blocklist+policy |
| E8 | USB/device hygiene | optional: external volume alert (not core v1) |

---

## 3. Priorisierte „Must before Pilot“ (Top 12)

Wenn nur 12 Dinge:

1. **Notarized signed binary + pkg**  
2. **Per-device API tokens** (kill shared key)  
3. **Bank default policy = log/ask**  
4. **No-cloud / EU-cloud switch**  
5. **Threat model + data inventory**  
6. **Persistent audit store** (fleet + local hash)  
7. **SSO Admin UI**  
8. **SIEM export**  
9. **Jamf install path**  
10. **Privileged helper (least privilege)**  
11. **PII redaction in events**  
12. **DPA + pen-test plan**

Alles andere ist Differenzierung, kein Gate.

---

## 4. Architektur-Zielbild (Bank Tier)

```
┌─────────────────────────────────────────────────────────────┐
│  Jamf / Intune                                              │
│   · deploy pkg · PPPC · config profile (policy seed)        │
└───────────────────────────┬─────────────────────────────────┘
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Mac: heald (signed)                                        │
│   collectors → policy engine → self-heal (consent)          │
│   local audit (append-only) → privileged helper             │
│   AI: Apple Intelligence only (optional, offline)           │
└───────────┬─────────────────────────────┬───────────────────┘
            │ mTLS / device token         │ syslog/CEF
            ▼                             ▼
┌───────────────────────┐      ┌──────────────────────┐
│  heald Control Plane  │      │  SOC SIEM            │
│  EU region / on-prem  │      │  Splunk / Sentinel   │
│  · fleet · policy     │      └──────────────────────┘
│  · approvals · RBAC   │
│  · SSO (Entra/Okta)   │
└───────────┬───────────┘
            │
            ▼
     ServiceNow / Jira (optional)
```

**Hard rules for bank tier:**

- Kein shared fleet API key  
- Kein Cloud-LLM mit Endpoint-Daten  
- Kein unsigned auto-update aus GitHub latest  
- Kein default `consent=auto` destruktiver Actions  
- Telemetry minimize + redact  

---

## 5. Zeitplan (indikativ)

| Phase | Dauer | Ergebnis |
|-------|-------|----------|
| **A** Pilot Ready | 6–10 W | Notarized, safe defaults, local audit, no-cloud |
| **B** Control Plane | 8–14 W | Real fleet, SSO, SIEM, device auth |
| **C** MDM Fit | 6–10 W (∥ B) | Jamf/Intune native |
| **D** Commercial/GRC | 3–6 M (∥) | DPA, pen-test, SLA, on-prem option |
| **E** Aggressive Heal | nach A+C | Controlled remediation catalog |

**Minimal path to first bank conversation:** A1–A10 + D1 draft + Architecture one-pager (~2 Monate fokussiert).  
**Minimal path to paid pilot:** A + B1–B4 + C1 + D1/D6 (~4–5 Monate).  
**Minimal path to „besteht Review“:** A+B+C+D Kern (~9–12 Monate mit 2–3 Eng).

---

## 6. Was wir bewusst *nicht* bauen (Elon-Schnitt)

| Vermeiden | Grund |
|-----------|--------|
| Eigenes EDR ersetzen (CrowdStrike etc.) | Bank hat EDR; heald = heal/ops, nicht AV |
| Windows-Agent v1 | Fokus Mac; später |
| Consumer App Store first | Bank will pkg/MDM |
| Aggressive AI shell freeform | Compliance nightmare |
| Shared demo keys in prod | Instant fail |
| US-only SaaS ohne AVV | DSGVO/DORA fail |

**Positionierung:**  
> „heald is the self-healing layer on top of your Mac fleet — policy-controlled, audit-first, on-device AI optional. Complements Jamf + EDR; does not replace them.“

---

## 7. Nächste 30 Tage (konkrete Engineering-Backlog)

1. `bank` Policy preset + `HEALD_CLOUD=0`  
2. Device enrollment token (replace shared key)  
3. Notarization pipeline in CI  
4. Pkg installer + uninstall  
5. Compliance export v2 (serial, MDM, CIS subset)  
6. Event PII redaction  
7. Threat-model.md + data-flow diagram  
8. SIEM syslog sink (local first)  
9. Dashboard: durable store (Postgres EU) spike  
10. One-pager „heald for regulated enterprises“ (DE/EN)

---

## 8. Success Metrics (Pilot)

| Metric | Target |
|--------|--------|
| Mean time to remediate disk/RAM alerts | &lt; 15 min unattended (consent=auto pilot group) |
| False positive destructive actions | 0 in pilot |
| Security findings critical open | 0 before expand |
| Audit completeness (action → log → fleet) | 100% |
| Install via Jamf success rate | &gt; 98% |
| Data residency | 100% EU or on-prem |

---

## 9. Fazit

**Heute:** starker **Mac self-heal core** mit Policy-Ansatz — gut als *Demo / lab*.  

**Für Deutsche Bank:** noch kein Produkt-Gate bestanden. Die Lücken sind nicht „mehr Collectors“, sondern:

1. **Trust** (signing, least privilege, no shared secrets)  
2. **Control** (MDM, SSO, remote policy, approval)  
3. **Evidence** (audit, SIEM, compliance packs)  
4. **Legal/Ops** (DPA, EU/on-prem, SLA, pen-test)

Die Roadmap priorisiert **A → B/C → D**, Features (E) zuletzt.  
Ohne A–D ist „besteht bei der DB“ Marketing; mit A–D ist es ein ernsthafter Pilot-Kandidat.
