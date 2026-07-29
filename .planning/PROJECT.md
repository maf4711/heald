# heald

## What This Is

Ein selbstheilender macOS-Systemwaechter, der als Daemon permanent im Hintergrund laeuft. Er ueberwacht Systemressourcen, Prozessstabilitaet und Systemgesundheit, greift bei Problemen automatisch ein (mit Ollama AI-Unterstuetzung) und protokolliert alles. Ein zentrales Web-Dashboard auf heald.sh (gehostet via Vercel) zeigt alle verbundenen Macs mit Live-Status, Activity-Feed und historischen Daten. AI-Fixes werden klar markiert.

## Core Value

macOS laeuft stabil und performant ohne manuelles Eingreifen — Probleme werden erkannt und automatisch behoben, bevor der User sie bemerkt. Alle Aktionen sind im zentralen Dashboard nachvollziehbar.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Permanente Hintergrund-Ueberwachung als LaunchAgent/Daemon
- [ ] Performance-Monitoring: CPU, RAM, Disk Space, Swap, S.M.A.R.T.
- [ ] Automatisches Beenden von RAM-/CPU-Fressern und haengenden Prozessen
- [ ] Abgestuerzte kritische Apps erkennen und neustarten
- [ ] Systemgesundheit pruefen: kaputte Plists, verwaiste Launch Agents, DNS
- [ ] Automatische Reparatur von Systemproblemen ohne Nachfrage
- [ ] Homebrew-Pakete und macOS-Updates ueberwachen
- [ ] Detailliertes Logging aller erkannten Probleme und durchgefuehrten Fixes
- [ ] Ollama AI-Integration fuer intelligente Entscheidungen und Zusammenfassungen
- [ ] Zentrales Web-Dashboard auf heald.sh via Vercel
- [ ] Alle Macs im Dashboard sichtbar mit Live-Status
- [ ] AI-Fixes klar markiert im Dashboard
- [ ] Taeglicher E-Mail-Report um 18:00 an foellmer@mac.com
- [ ] macOS Native Notifications bei kritischen Events
- [ ] Multi-Machine Setup mit One-Liner Install
- [ ] Git-Repository fuer Verteilung

### Out of Scope

- Native macOS App (SwiftUI) — CLI + Web-Dashboard reichen
- iOS/iPad-Ueberwachung — nur macOS
- Antivirus/Malware-Scanning — Fokus auf Systemgesundheit, nicht Security

## Context

- Zielplattform: macOS (Darwin 25.4.0, Apple Silicon)
- Laeuft auf dem Rechner des Users als LaunchAgent
- Muss mit macOS-Sicherheitsmodell arbeiten (SIP, TCC, Gatekeeper)
- Homebrew ist als Paketmanager vorhanden
- User will keine Interaktion — alles soll automatisch passieren
- Dashboard gehostet auf Vercel unter heald.sh
- Mehrere Macs sollen ueberwacht und zentral angezeigt werden
- Alles was fehlt wird automatisch via Homebrew installiert (inkl. Ollama)
- E-Mail-Report via lokales macOS Mail-System (sendmail)

## Constraints

- **Plattform**: macOS only — nutzt macOS-spezifische APIs und Tools (launchctl, diskutil, etc.)
- **Berechtigungen**: Muss innerhalb der macOS-Sicherheitsgrenzen arbeiten (SIP bleibt aktiv)
- **Ressourcen**: Der Daemon selbst darf minimal CPU/RAM verbrauchen
- **Stabilitaet**: Darf das System nicht destabilisieren durch aggressive Eingriffe
- **Hosting**: Dashboard auf Vercel, Domain heald.sh
- **Datenschutz**: Metriken werden an Cloud-Dashboard gesendet — nur ueber authentifizierte API

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| CLI + Web statt native App | Schneller zu bauen, weniger Overhead, User will Terminal | — Pending |
| Automatisch fixen ohne Nachfrage | User will keine Interaktion, nur Ergebnisse sehen | — Pending |
| Vercel-gehostetes Dashboard statt localhost | Zentrales Dashboard fuer mehrere Macs, erreichbar unter heald.sh | — Pending |
| Ollama AI fuer Entscheidungen | Intelligentere Kill-Entscheidungen statt nur fester Thresholds | — Pending |
| Swift Daemon + Next.js Dashboard | Swift fuer nativen macOS-Zugriff, Next.js/Vercel fuer Web-Dashboard | — Pending |
| Projektname: heald | Kurz, praegnant, steht fuer "healing daemon" | — Pending |

---
*Last updated: 2026-03-03 after roadmap revision*
