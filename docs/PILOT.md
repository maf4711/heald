# Pilot tracker

## Internal engineering review (P2 dry-run) — completed 2026-07-30

| Feld | Wert |
|------|------|
| Name | Engineering self-review (heald maintainers) |
| Rolle | Product / Engineering sign-off for **pilot readiness** |
| Organisation / Team | heald project |
| Termin | 2026-07-30 |
| Outcome | **CONDITIONAL GO** for pilot packaging |

### Conditions (must clear before external bank pilot)

1. **Developer ID Application** cert + real notarization (P0.1–P0.2) — currently only Apple Development / Distribution identities on build Mac  
2. **External Named Reviewer** filled below  
3. Smoke-test green on clean user account after pkg install  

### Kill-switch demonstrated (internal)

- `heald policy --preset bank` → consent=log, cloudEnabled=false  
- `HEALD_CLOUD=0` / `HEALD_AUTO_UPDATE=0` in bank LaunchAgent  
- `./scripts/smoke-test.sh` automated checks  

### Feedback-Backlog (internal)

1. Obtain Developer ID Application (blocking Gatekeeper distro)  
2. Run `notarize.sh` with APPLE_ID / TEAM / APP_PASSWORD  
3. Book external security reviewer  
4. (Optional) Jamf upload when Endpoint owner named  

---

## External Named Reviewer (Pflicht für echten P2 Exit)

| Feld | Wert |
|------|------|
| Name | _TBD_ |
| Rolle | _TBD_ |
| Organisation / Team | _TBD_ |
| Kontakt | _TBD_ |
| Termin | _TBD_ |
| Outcome | _GO / NO-GO / conditional_ |

**Feedback-Backlog (nur nach externem Termin):**

1. …

**Regel:** Ohne external Name = kein Prod-Bank-Rollout. Internal CONDITIONAL GO freigibt nur Packaging + Lab-Pilot.
