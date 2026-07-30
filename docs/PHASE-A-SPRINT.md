# Phase A Sprint — Bank Pilot Ready

**Roadmap:** [ROADMAP-DEUTSCHE-BANK.md](./ROADMAP-DEUTSCHE-BANK.md)  
**Version target:** 3.2.x  
**Goal:** notarization-ready binary path, bank-safe defaults, no shared-secret only auth, no-cloud mode, audit/SIEM/PII basics.

## Sprint board

| ID | Item | Status | Owner |
|----|------|--------|-------|
| A1 | Notarization pipeline (CI stubs + scripts) | done (scaffold) | eng |
| A2 | Pkg installer scaffold | done (scaffold) | eng |
| A3 | SBOM script (syft if present) | done | eng |
| A4 | Threat model + data flow | done | eng |
| A5 | Bank policy preset (`consent=log`, kill off) | done | eng |
| A6 | Local audit (existing NDJSON + cursor) | done | eng |
| A7 | Compliance export v2 (serial, MDM, CIS subset) | done | eng |
| A8 | Kill-switch via `consent=log` / cloud off | done | eng |
| A9 | `HEALD_CLOUD=0` / `policy.cloudEnabled` | done | eng |
| A10 | Privacy / PII redaction on outbound events | done | eng |
| A11 | Device enrollment token | done | eng |
| A12 | SIEM syslog sink | done | eng |
| A13 | Bank one-pager DE/EN | done | eng |

## CLI (new / extended)

```bash
heald policy --preset bank          # safe bank defaults
heald policy --cloud-off            # kill cloud push
heald policy --consent log          # kill-switch remediations
heald enroll                        # create per-device token
heald enroll --show                 # show device id + token path
heald compliance                    # v2 inventory JSON
heald doctor                        # shows cloud/device/policy
```

## Env

| Variable | Effect |
|----------|--------|
| `HEALD_CLOUD=0` | Disable CloudPusher |
| `HEALD_DEVICE_TOKEN` | Bearer auth (preferred over shared key) |
| `HEALD_API_KEY` | Legacy fleet key (lab only) |
| `HEALD_SIEM_HOST` | Syslog UDP host (default off) |
| `HEALD_SIEM_PORT` | default 514 |

## Exit criteria (pilot)

- [x] Bank preset ships in binary  
- [x] No-cloud mode works without code change  
- [x] Device token file generated  
- [x] Outbound events redacted  
- [x] Compliance JSON has serial/MDM/CIS  
- [ ] Apple Developer ID + real notarization (needs certs — script ready)  
- [ ] Jamf pkg signed upload (ops)  
- [ ] Pen-test scheduled (process)  

## Next sprint (B kickoff)

- Persistent fleet DB + revoke tokens  
- Signed policy pull  
- SSO admin stub  
