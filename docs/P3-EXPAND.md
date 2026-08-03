# P3 Expand — demand-gated recipes

**Regel:** Nur mit **Namen** in `docs/PILOT.md` Feedback starten.

## P3.a Jamf

| Artefakt | Pfad |
|----------|------|
| Bank LaunchAgent template | `launchd/com.heald.daemon.bank.plist` |
| Pkg builder | `scripts/build-pkg.sh` |
| Profile seed (Managed Preferences) | `config/jamf/sh.heald.plist` |

**Jamf flow:** Upload `dist/heald-*.pkg` → policy → scope pilot group.  
Policy seed can push `consent=log` via script: `heald policy --preset bank`.

## P3.b SIEM

```bash
heald policy --siem-host splunk-hf.example.com
# or
export HEALD_SIEM_HOST=siem.example.com
export HEALD_SIEM_PORT=514
```

Code: `Sources/heald/Enterprise/SyslogSink.swift`  
Test: `./scripts/siem-test.sh` (local UDP listener optional).

## P3.c Device-Token Registry

Today: token in `~/.heald/device.json`, server accepts as `HEALD_API_KEYS` entry.  
Next (when named): allow-list table deviceId→token, revoke endpoint.

## P3.d Signed update channel

Bank: `HEALD_AUTO_UPDATE=0` forever until signed channel.  
Lab: `heald update` + `/api/update` manifest.

## P3.e Consent=ask

```bash
heald policy --consent ask
```

Remediation blocked; notifications only (`allowsRemediation() == false`).

## P3.f Controlled remediate

After 90d pilot + Security GO: enable single toggles in policy  
(`ramPurgeEnabled`, `diskCleanupEnabled`) one at a time — never full `consent=auto` day-one.

## P3.g Fleet EU + SSO

Out of scope until paid deal. Lab dashboard `heald.sh` remains lab.

## P3.h DPA / Pen-Test / SLA

Templates: `docs/legal/DPA-OUTLINE.md`  
Pen-test: after first external GO, not before.

## Activation log

| ID | Requested by | Date | Status |
|----|--------------|------|--------|
| — | — | — | none active |
