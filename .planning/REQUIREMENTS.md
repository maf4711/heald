# Requirements: heald

**Defined:** 2026-03-03
**Core Value:** macOS laeuft stabil und performant ohne manuelles Eingreifen — Probleme werden erkannt und automatisch behoben, bevor der User sie bemerkt. Alle Aktionen sind im zentralen Dashboard nachvollziehbar.

## v1 Requirements

### Daemon Core

- [x] **DAEM-01**: Daemon laeuft persistent als LaunchAgent (startet bei Login, ueberlebt Reboot)
- [x] **DAEM-02**: Daemon behandelt SIGTERM von launchd sauber ohne Datenverlust
- [x] **DAEM-03**: Daemon verbraucht selbst minimal CPU/RAM (< 1% CPU, < 50MB RAM im Idle)
- [x] **DAEM-04**: Install-Script installiert alle Abhaengigkeiten via Homebrew (inkl. Ollama)
- [x] **DAEM-05**: Uninstall-Script entfernt Daemon und LaunchAgent sauber

### Monitoring

- [ ] **MON-01**: CPU-Auslastung ueberwachen (gesamt + pro Core, 5s Polling)
- [ ] **MON-02**: RAM/Memory Pressure ueberwachen (Used, Wired, Compressed, Swap)
- [ ] **MON-03**: Disk Space pro Volume ueberwachen
- [ ] **MON-04**: Disk I/O Activity ueberwachen
- [ ] **MON-05**: Prozessliste mit CPU/RAM pro Prozess erfassen
- [ ] **MON-06**: Top-Ressourcenverbraucher identifizieren und ranken
- [ ] **MON-07**: Swap-Spikes erkennen und verursachenden Prozess loggen
- [ ] **MON-08**: S.M.A.R.T. Disk Health ueberwachen

### Self-Healing

- [ ] **HEAL-01**: Haengende Prozesse automatisch killen (sustained >90% CPU ueber 5min, nicht auf Safelist)
- [ ] **HEAL-02**: SIGTERM zuerst, SIGKILL als Fallback nach Timeout
- [ ] **HEAL-03**: Safelist fuer System-Prozesse die nie gekillt werden (kernel_task, WindowServer, loginwindow, launchd, etc.)
- [ ] **HEAL-04**: Abgestuerzte kritische Apps erkennen und automatisch neustarten (konfigurierbare Watch-List)
- [ ] **HEAL-05**: DNS-Probleme erkennen und Cache automatisch flushen
- [ ] **HEAL-06**: Verwaiste LaunchAgents erkennen (Plist vorhanden aber Binary fehlt)
- [ ] **HEAL-07**: Kaputte Plists erkennen via plutil-Validation

### AI Integration

- [ ] **AI-01**: Ollama-Anbindung fuer Fehleranalyse (Problem erkennen → LLM analysiert Kontext → beste Loesung waehlen)
- [ ] **AI-02**: Ollama entscheidet intelligent ob ein Prozess gekillt werden soll (statt nur fester Thresholds)
- [ ] **AI-03**: Ollama fasst taegliche Activity Logs zusammen (natuerlichsprachige Zusammenfassung)
- [ ] **AI-04**: Ollama installieren via Homebrew falls nicht vorhanden
- [ ] **AI-05**: Fallback auf regelbasierte Entscheidungen wenn Ollama nicht verfuegbar

### Cloud Dashboard and API

- [ ] **CLOUD-01**: Next.js Web-App auf Vercel deployed, erreichbar unter heald.meradOS.com
- [ ] **CLOUD-02**: Cloud-API (Vercel API Routes) nimmt Metriken von Daemons per HTTP POST entgegen
- [ ] **CLOUD-03**: Daemon authentifiziert sich per API-Key gegen Cloud-API (kein unauth. Push moeglich)
- [ ] **CLOUD-04**: Daemon puffert Metriken lokal wenn Cloud nicht erreichbar und sendet nach Wiederverbindung nach
- [ ] **CLOUD-05**: Dashboard zeigt alle verbundenen Macs mit Live-Status und zuletzt gesehenem Zeitstempel
- [ ] **CLOUD-06**: Git-Repository fuer Verteilung; One-Liner Install-Script fuer neue Rechner
- [ ] **DASH-02**: Chronologischer Activity Feed (was wann erkannt und gefixt wurde) im Cloud-Dashboard
- [ ] **DASH-03**: Historische Charts fuer Metriken (CPU/RAM/Disk Verlauf ueber Zeit) im Cloud-Dashboard
- [ ] **DASH-04**: Dashboard zeigt Gesundheitsstatus aller ueberwachten Bereiche (grueen/gelb/rot) pro Maschine
- [ ] **DASH-05**: AI-Fixes werden klar als "AI" markiert und visuell von regelbasierten Fixes unterschieden

### Health Checks

- [ ] **HLTH-01**: Homebrew-Pakete auf Aktualitaet pruefen und im Dashboard anzeigen
- [ ] **HLTH-02**: Anstehende macOS Updates erkennen und anzeigen
- [ ] **HLTH-03**: Health Checks laufen auf eigenen Schedules (nicht bei jedem 5s-Tick)

### Notifications and Reporting

- [ ] **NOTF-01**: macOS Native Notifications bei kritischen Events (Prozess gekillt, Disk fast voll, App abgestuerzt)
- [ ] **NOTF-02**: Taeglicher E-Mail-Report um 18:00 Uhr an foellmer@mac.com
- [ ] **NOTF-03**: E-Mail-Versand ueber lokales macOS Mail-System (sendmail/postfix)
- [ ] **NOTF-04**: Report enthaelt AI-generierte Zusammenfassung des Tages

### Logging and Storage

- [ ] **LOG-01**: Strukturiertes JSON Activity Log aller Aktionen
- [ ] **LOG-02**: Metriken in SQLite speichern fuer historische Abfragen
- [ ] **LOG-03**: Log-Rotation/Retention (keine unbegrenzte Datenbankgroesse)
- [ ] **LOG-04**: Detailliertes Audit-Trail mit Before/After-State bei Fixes

## v2 Requirements

### Extended Features

- **EXT-01**: Cache und Temp-File Cleanup auf Schedule
- **EXT-02**: Spotlight Re-Index bei erkannten Suchproblemen
- **EXT-03**: Homebrew Auto-Upgrade (opt-in, per Package konfigurierbar)
- **EXT-04**: Push Notifications auf dem iPhone wenn ein Mac kritische Events hat

## Out of Scope

| Feature | Reason |
|---------|--------|
| Native macOS App (SwiftUI) | CLI + Web-Dashboard reicht, geringerer Entwicklungsaufwand |
| Antivirus / Malware Scanning | Anderes Bedrohungsmodell, nicht Fokus dieses Tools |
| Aggressive Memory Compression | macOS verwaltet das selbst, erzwingen verschwendet CPU |
| iOS/iPad Ueberwachung | Nur macOS |
| Automatisches Disk-Repair (fsck) | Zu riskant bei defekten Disks, nur Alert |
| Automatisches Homebrew-Upgrade (default) | Bricht Dev-Environments, nur Report in v1 |
| Localhost-only Dashboard | Durch Cloud-Dashboard ersetzt; mehrere Macs brauchen zentralen Zugangspunkt |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DAEM-01 | Phase 1 | Complete |
| DAEM-02 | Phase 1 | Complete |
| DAEM-03 | Phase 1 | Complete |
| DAEM-04 | Phase 1 | Complete |
| DAEM-05 | Phase 1 | Complete |
| MON-01 | Phase 2 | Pending |
| MON-02 | Phase 2 | Pending |
| MON-03 | Phase 2 | Pending |
| MON-04 | Phase 2 | Pending |
| MON-05 | Phase 2 | Pending |
| MON-06 | Phase 2 | Pending |
| MON-07 | Phase 2 | Pending |
| MON-08 | Phase 2 | Pending |
| LOG-01 | Phase 3 | Pending |
| LOG-02 | Phase 3 | Pending |
| LOG-03 | Phase 3 | Pending |
| LOG-04 | Phase 3 | Pending |
| CLOUD-01 | Phase 4 | Pending |
| CLOUD-02 | Phase 4 | Pending |
| CLOUD-03 | Phase 4 | Pending |
| CLOUD-04 | Phase 4 | Pending |
| CLOUD-05 | Phase 4 | Pending |
| CLOUD-06 | Phase 4 | Pending |
| DASH-02 | Phase 4 | Pending |
| DASH-03 | Phase 4 | Pending |
| DASH-04 | Phase 4 | Pending |
| DASH-05 | Phase 4 | Pending |
| HEAL-01 | Phase 5 | Pending |
| HEAL-02 | Phase 5 | Pending |
| HEAL-03 | Phase 5 | Pending |
| HEAL-04 | Phase 6 | Pending |
| HEAL-05 | Phase 6 | Pending |
| HEAL-06 | Phase 6 | Pending |
| HEAL-07 | Phase 6 | Pending |
| HLTH-01 | Phase 6 | Pending |
| HLTH-02 | Phase 6 | Pending |
| HLTH-03 | Phase 6 | Pending |
| AI-01 | Phase 7 | Pending |
| AI-02 | Phase 7 | Pending |
| AI-03 | Phase 7 | Pending |
| AI-04 | Phase 7 | Pending |
| AI-05 | Phase 7 | Pending |
| NOTF-01 | Phase 7 | Pending |
| NOTF-02 | Phase 7 | Pending |
| NOTF-03 | Phase 7 | Pending |
| NOTF-04 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 46 total
- Mapped to phases: 46
- Unmapped: 0

---
*Requirements defined: 2026-03-03*
*Last updated: 2026-03-03 — Revised for heald rename, cloud dashboard architecture, multi-machine merged into Phase 4*
