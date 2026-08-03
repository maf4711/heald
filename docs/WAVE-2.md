# Wave 2 — Next wave after P0–P3 engineering

**Version:** 3.4.0  
**Date:** 2026-07-30

## Goal

Close the highest-value gaps **without** waiting for Developer ID or external bank reviewer:

1. MDM can actually **drive** policy  
2. Device tokens can **register** on fleet  
3. consent=ask has a real **approve** path  
4. CI catches doc/script/dashboard breakage  
5. Doctor tells truth about auto-update from LaunchAgent  

## Delivered

| Item | Artefakt |
|------|----------|
| Managed Preferences merge | `PolicyPack.applyManagedOverrides` domain `sh.heald` |
| Device registry API | `POST/GET /api/enroll` + `dashboard/src/lib/devices.ts` |
| Auth accepts device tokens | `auth.ts` + `HEALD_DEVICE_TOKENS` |
| Client register | `heald enroll --register` |
| One-shot approve | `heald approve <action>` + `ApprovalStore` |
| Doctor LaunchAgent auto-update | reads plist env |
| CI | `.github/workflows/ci.yml` (docs, dashboard, optional macos) |
| Release manifest helper | `scripts/release-manifest.sh` |

## Still human

| Item | Owner |
|------|--------|
| Developer ID Application + notary | Apple account |
| External Named Reviewer | Sales / network |
| Production durable device DB | after paid pilot (replace /tmp registry) |

## Commands

```bash
# MDM: deploy config/jamf/sh.heald.plist as preference domain sh.heald
heald doctor   # MDM policy: active

# Fleet register (admin key = HEALD_API_KEYS entry)
export HEALD_ADMIN_KEY=…
heald enroll --register

# consent=ask flow
heald policy --consent ask
heald approve ram_purge --ttl-minutes 30

./scripts/smoke-test.sh
./scripts/release-manifest.sh
```
