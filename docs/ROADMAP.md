# heald Roadmap

**Stand:** 2026-07-30 · Product **3.4.0**  
**Methode:** [ELON-CUT-BANK.md](./ELON-CUT-BANK.md) · **Wave 2:** [WAVE-2.md](./WAVE-2.md)

---

## One-liner

> **Bank pilot** = signierter Mac-Sensor + log-only + lokales Audit + eine Compliance-JSON + Kill-Switch.  
> Expand (SIEM/Jamf/Fleet) nur mit Named Ask.

---

## Phase status (execution board)

| Phase | Status | Notes |
|-------|--------|--------|
| **P0 Trust** | ✅ eng / ⚠️ cert | pkg + bank install + uninstall done; **Developer ID Application** still missing on build Mac |
| **P1 Pilot Pack** | ✅ | smoke-test, reviewer-pack, bank LaunchAgent, LAB/BANK docs |
| **P2 First Review** | ✅ internal / ⏳ external | Internal **CONDITIONAL GO** in [PILOT.md](./PILOT.md); external Named Reviewer TBD |
| **P3 Expand** | ✅ recipes ready | Demand-gated stubs in [P3-EXPAND.md](./P3-EXPAND.md) — nothing activated without name |

### Wave 2 (shipped in 3.4.0)

| Item | Status |
|------|--------|
| MDM `sh.heald` policy merge | ✅ |
| `/api/enroll` device registry | ✅ |
| `heald enroll --register` | ✅ |
| `heald approve <action>` | ✅ |
| Doctor LaunchAgent auto-update | ✅ |
| CI (docs + dashboard + optional macos) | ✅ |

### Blockers (human, not code)

| Blocker | Who | Unblocks |
|---------|-----|----------|
| Developer ID Application + notary login | Apple Developer account owner | Gatekeeper-safe distro (P0.2 complete) |
| External Named Reviewer | Sales / network | Real P2 Exit for bank |

---

## P0 — Trust

| # | Deliverable | Status | Artefakt |
|---|-------------|--------|----------|
| P0.1 | Dev ID cert | ⚠️ | `scripts/trust-status.sh` — currently Apple Development + Distribution only |
| P0.2 | Notarize script | ✅ scaffold | `scripts/notarize.sh` (needs Dev ID) |
| P0.3 | Installable pkg | ✅ | `scripts/build-pkg.sh` → `dist/heald-*.pkg` |
| P0.4 | Bank postinstall | ✅ | bank preset + enroll + CLOUD=0 + AUTO_UPDATE=0 |
| P0.5 | Uninstall | ✅ | `uninstall.sh` (+ `HEALD_PURGE_DATA=1`) |
| P0.+ | Bank local install | ✅ | `scripts/install-bank.sh` |

---

## P1 — Pilot Pack

| # | Deliverable | Status | Artefakt |
|---|-------------|--------|----------|
| P1.1 | Reviewer ZIP | ✅ | `scripts/reviewer-pack.sh` |
| P1.2 | Bank LaunchAgent | ✅ | `launchd/com.heald.daemon.bank.plist` |
| P1.3 | Doctor bank lines | ✅ | 3.2+ doctor output |
| P1.4 | Smoke checklist | ✅ | `docs/SMOKE-TEST.md` + `scripts/smoke-test.sh` |
| P1.5 | Lab vs Bank | ✅ | SMOKE-TEST.md table + bank install path |

---

## P2 — First Review

| # | Deliverable | Status |
|---|-------------|--------|
| P2.1 Named person | ✅ internal eng / ⏳ external in PILOT.md |
| P2.2 Termin | ✅ internal 2026-07-30 |
| P2.3 Feedback backlog | ✅ internal conditions listed |
| P2.4 Kill-switch demo | ✅ smoke-test + bank preset |

---

## P3 — Expand (on demand)

All recipes prepared, **none activated**:

| ID | Recipe |
|----|--------|
| P3.a Jamf | `config/jamf/sh.heald.plist` + pkg |
| P3.b SIEM | SyslogSink + `scripts/siem-test.sh` |
| P3.c Token registry | documented in P3-EXPAND |
| P3.d Signed updates | AUTO_UPDATE=0 until named |
| P3.e consent=ask | `heald policy --consent ask` |
| P3.f Remediate catalog | policy toggles, gradual |
| P3.g Fleet EU/SSO | post-deal only |
| P3.h DPA | `docs/legal/DPA-OUTLINE.md` |

Activation log: [P3-EXPAND.md](./P3-EXPAND.md)

---

## How to run the full pilot path

```bash
# Trust + install (bank)
swift build -c release
./scripts/trust-status.sh
./scripts/install-bank.sh
./scripts/smoke-test.sh

# Package
./scripts/build-pkg.sh

# Reviewer ZIP
./scripts/reviewer-pack.sh

# Uninstall
./uninstall.sh
```

---

## Success metrics (current)

| Metric | Target | Current |
|--------|--------|---------|
| Reviewer ZIP | exists | ✅ `dist/heald-reviewer-pack-*.zip` |
| Bank false remediation | 0 | bank preset log-only ✅ |
| Outbound bank mode | 0 | cloud off ✅ |
| Notarized binary | yes | ⚠️ blocked on Dev ID |
| External security GO | yes | ⏳ TBD |

---

## Versioning

| Version | Meaning |
|---------|---------|
| 3.2.x | Phase A features + algo cut |
| 3.3.0 | P0–P3 engineering complete |
| **3.4.0** | Wave 2: MDM merge, device registry, approve, CI |
| 3.4.x+notarized | After Developer ID notary success |
| 3.5.x | After **external** Named Reviewer GO |

---

*Roadmap complete for engineering scope. Human blockers remain explicit.*
