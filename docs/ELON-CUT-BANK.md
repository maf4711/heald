# Elon-Algo Cut — heald × „Deutsche Bank“

**Angewendet auf:** Roadmap + Phase A (Stand 3.2.0)  
**Datum:** 2026-07-30  
**Regel:** 5 Schritte strikt in Reihenfolge. Kein Optimieren vor Löschen.

---

## First Principles (vor Schritt 1)

**Physikalische/logische Wahrheit:**  
Eine Bank kauft kein „Self-Heal-Feature-Set“. Sie kauft **Risikoreduktion mit Nachweis**, ohne **neue Angriffsfläche** und ohne **Datenabfluss**.

**Was „bestehen“ wirklich ist (1 Satz):**  
Ein Security-Mensch kann in **einem Termin** sagen: *was läuft, was darf es, was verlässt den Mac, wie schalte ich es aus* — und das Binary ist **signiert/vertrauenswürdig**.

Alles andere ist Theater oder später.

---

## Schritt 1 — Make Requirements Less Dumb

Jede Anforderung: *Wer? Warum? Was passiert wenn NICHT?*

| Anforderung (Roadmap) | Wer verlangt das? | Zurückgewiesen? | Urteil |
|----------------------|-------------------|-----------------|--------|
| Self-Heal auto-fix bei DB | Produkt-Idee (wir) | Ja: Bank will **Kontrolle vor Automagic** | **Streichen für Pilot.** Log-only reicht. |
| Fleet Dashboard (heald.sh) | wir / Demo | Ja: Vercel-Memory ist **Anti-Bank** | **Streichen für Bank-Tier.** Lab only. |
| SIEM Syslog in Phase A | „SOC erwartet…“ (anonym) | Ja: ohne Kunden-SOC-Ziel = YAGNI | **Streichen bis ein Named SOC es will.** |
| CIS full benchmark | Compliance-Folklore | Ja: 6 Checks reichen für Demo | **Subset behalten, Rest streichen.** |
| SSO / Entra / Okta | IAM-Standard | Ja: für 20 Mac Pilot = Overkill | **Später.** |
| Org/Tenant/Site Modell | Enterprise-SaaS-Kopie | Ja | **Streichen.** |
| On-Prem Appliance | „Banken wollen On-Prem“ | Ja: erst wenn Deal | **Streichen bis RFP.** |
| SOC2 / ISO 27001 | GRC-Checkliste | Ja: Pilot braucht **Threat Model + DPA-Draft**, nicht Zertifikat | **Später.** |
| Pen-Test extern | Security | Teilweise: vor Prod-Rollout ja, vor lab-Pilot nein | **Nach erstem internen Review.** |
| Device Token + enroll | Security (shared key fail) | Nein — shared key ist realer Fail | **Behalten.** |
| Bank policy consent=log, cloud off | Security / du | Nein | **Behalten.** |
| Notarized / signed binary | Mac Engineering / Gatekeeper | Nein — ohne das kein Jamf-Pfad | **Behalten (echtes Signing, nicht nur Script).** |
| Pkg statt curl\|bash | Change Management | Nein für >5 Macs | **Behalten (minimal).** |
| Threat model 1-pager | Security Review | Nein | **Behalten.** |
| Compliance JSON export | Audit / Gespräch | Nein als **1 Datei** | **Behalten (eine Datei, keine Frameworks).** |
| PII redaction outbound | DSGVO | Nur wenn Cloud/SIEM an | **Behalten solange Outbound existiert; bei cloud-off fast irrelevant.** |
| Auto-Update vom Server | Ops-Bequemlichkeit | Ja: Update-Pfad = Angriffsfläche | **Bank: aus, bis signed channel.** |
| Apple Intelligence Self-Heal | Marketing | Ja: Bank misstraut AI-Aktionen | **Pilot: aus. Optional lab.** |
| Webhooks Slack | Ops | Ja | **Streichen default.** |
| Process kill / crash quarantine auto | Heal-Features | Ja | **Streichen default (bereits bank preset).** |
| 9–12 Monate Phasen B–E | „Enterprise Reife“ | Ja: **Idiot Index** — Monate ohne Kundenfeedback | **Ersetzen durch 2-Wochen-Zyklen mit 1 Named Stakeholder.** |

### Was bleibt (nur das)

1. **Signiertes Binary + installierbares Paket** (vertrauenswürdiger Code)  
2. **Bank-Mode: nur beobachten + loggen + exportieren** (kein Auto-Damage)  
3. **Cloud default OFF**  
4. **Device-Identität** (kein shared secret in Prod)  
5. **Eine Compliance/Audit-Datei** die man dem Security-Mensch gibt  
6. **Threat Model (1 Seite)**  
7. **Kill-switch** (`consent=log` / cloud off) — schon Policy  

### Was gestrichen wird (Anforderungsebene)

- „DB-ready“ als 5-Phasen-Enterprise-Plattform  
- SIEM/SSO/On-Prem/SOC2 als **jetzt**-Pflicht  
- Aggressive Self-Heal als Verkaufsargument für Bank  
- Fleet-Cloud als Muss  
- Feature-Vollständigkeit vor erstem Named Reviewer  

**Warum:** Wenn wir das NICHT bauen, passiert oft **nichts Schlimmes** — außer wir treffen nie einen realen Reviewer. Dann ist die teure Plattform nutzlos.

---

## Schritt 2 — Delete the Part or Process

**Löschen > optimieren.** Ziel: mind. 10 % muss man später bereuen und zurückholen.

### Löschen / nicht weiterbauen (Roadmap & Scope)

| Teil | Aktion |
|------|--------|
| Phase B (Control Plane) als Block | **Delete** bis Pilot-Feedback |
| Phase C full Intune+Jamf dual | **Delete** → max. **ein** MDM-Pfad wenn Kunde genannt |
| Phase D Zertifikate vor Pilot | **Delete** aus Engineering-Critical-Path |
| Phase E aggressive heal catalog | **Delete** aus Bank-Story |
| SyslogSink als Prio | **Park** (Code darf liegen, kein Fokus) |
| SBOM-Stub-Pflege | **Delete** Aufwand bis syft+Release real |
| Hash-chain immutable audit | **Delete** (NDJSON reicht Pilot) |
| Privacy-Manifest-Doku-Serie | **Delete** → 10 Zeilen in Threat Model |
| Dashboard-Persistenz-Spike | **Delete** für Bank (cloud off) |
| Multi-preset Lab/Bank Complexity Story | **Simplify** → Bank = default für regulated talk |
| Auto-Update in Bank installs | **Off** in pkg/LaunchAgent |

### Was übrig bleibt (nur begründen was BLEIBT)

| Teil | Warum absolut nötig |
|------|---------------------|
| **Daemon + Collectors (bestehend)** | Ohne Beobachtung kein Produkt |
| **Activity log lokal** | Nachweis was der Agent „sah“ |
| **Policy consent=log + cloud off** | Ohne das kein Security-OK |
| **`heald compliance` JSON** | Ein Artefakt für den Termin |
| **`heald enroll` Device-ID** | Hardware-Bezug im Report |
| **Threat model 1-pager** | Reviewer liest das zuerst |
| **Signed pkg path** | Ohne Trust keine Installation |
| **Doctor** | 30-Sekunden-Zustand |

**Erwartung:** Später holen wir ~10–20 % zurück (z.B. SIEM wenn SOC named, Jamf wenn Endpoint named). Wenn **nichts** zurückkommt, war das Löschen noch zu zaghaft.

---

## Schritt 3 — Simplify and Optimize

**Nach dem Löschen.** Keine Cleverness.

### Vereinfachte Zieldefinition

> **heald Bank Pilot = signed Mac sensor + local audit + one JSON export + off-by-default cloud/actions.**

### Vereinfachte Customer Journey (Pilot)

```
1. Install pkg (signed)
2. heald policy --preset bank   # or preset baked into pkg postinstall
3. heald enroll
4. heald compliance > report.json
5. Optional: zip ~/.heald/data/activity.ndjson
6. Meeting: Threat Model + report.json
```

Kein Dashboard. Kein SIEM. Kein SSO. Kein Auto-Heal.

### Gegen Ausgangszustand (Roadmap 5 Phasen / 12 Monate)

| Vorher | Nachher |
|--------|---------|
| 5 Phasen, 40+ Deliverables | **1 Pilot-Loop, 7 Deliverables** |
| Control Plane vor Feedback | **Feedback vor Control Plane** |
| „Bestehen bei DB“ = Plattform | „Bestehen“ = **1 Security-Termin bestanden** |
| Features demonstrieren Heal | Features demonstrieren **Kontrolle** |

### Code-Komplexität (bewusst nicht anfassen im Algo-Lauf)

Bereits gebautes (Syslog, Redactor, …) **nicht löschen im Repo-Brand** — aber **nicht erweitern**. Wartung = zero. Fokus = Signing + eine Install-Story.

---

## Schritt 4 — Accelerate Cycle Time

**Nach Vereinfachung.**

| Zyklus | Vorher | Nachher | Faktor |
|--------|--------|---------|--------|
| „Bank-ready Feature“ | Wochen Roadmap | **2-Wochen-Pilot** max | ~5–10× |
| Security-Feedback | nach monatelangem Build | **nach 1 signed pkg + JSON** | ~20× |
| Install-Test | curl + LaunchAgent hand | **ein pkg, ein doctor** | ~3× |
| Policy-Demo | Doku lesen | **`heald policy --preset bank`** (schon da) | instant |
| Compliance-Artefakt | manuell sammeln | **`heald compliance`** (schon da) | instant |
| Notarize/sign | unklar / manuell später | **Script + 1 Cert-Setup, dann <30 min/release** | sobald Cert da |

### Parallel (nur das)

- **Track Cert:** Apple Developer ID (du / Account) — Blocker, nicht Code  
- **Track eng:** pkg postinstall immer `preset bank` + enroll  
- **Track sales/sec:** Named Reviewer finden (Name, nicht „die Bank“)  

Ohne **Named Person** bei DB/Konzern ist jeder weitere Monat Engineering = Theater.

---

## Schritt 5 — Automate

**Zuletzt.** Nur den schlanken Prozess.

| Automatisieren | Manuell lassen |
|----------------|----------------|
| `swift build -c release` + `build-pkg.sh` in CI | Cert-Kauf, Notary credentials |
| postinstall: bank preset + enroll | Ersten Security-Termin führen |
| `compliance` JSON an fester Path | Reviewer-Feedback interpretieren |
| — | Policy-Ausnahmen pro Kunde |
| — | DPA/Legal |

**Nicht automatisieren:**  
Auto-Heal freischalten, Fleet-Push, SIEM-Pipeline, SSO — das automatisiert einen Prozess den wir gelöscht haben.

---

## Idiot Index (ehrlich)

| Input | Output-Wert |
|-------|-------------|
| 12 Monate Enterprise-Plattform | 0 Reviews ohne Named Stakeholder |
| Phase-A Feature-Fläche (SIEM, PII, …) | Teilweise nützlich, **Übergewicht** vs. Signing |
| 1 signed pkg + compliance JSON + threat model | **Maximaler Reviewer-Wert pro Stunde** |

Idiot Index war hoch bei „Plattform vor Gespräch“. Algo-Cut senkt ihn.

---

## Konkrete nächste 14 Tage (nach Algo)

1. **Apple Developer ID** besorgen / freischalten (Mensch, nicht Code)  
2. **Einmal** `notarize.sh` + `build-pkg.sh` echt durchziehen  
3. Pkg postinstall: **immer bank preset** (1 PR)  
4. Auto-Update im Bank-LaunchAgent **HEALD_AUTO_UPDATE=0**  
5. **Named Reviewer** (Name in Doc) — sonst Pause Engineering  

### Nicht in den 14 Tagen

- Postgres Fleet  
- SSO  
- SIEM polish  
- CIS full  
- On-Prem  
- Mehr Collectors  

---

## Ein Satz

**Lösche die Enterprise-Fantasie. Behalte den Sensor mit Kill-Switch und einem Report. Signiere ihn. Sprich mit einem Menschen der „Nein“ sagen darf.**
