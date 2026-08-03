# DPA / AVV Outline (P3.h — not a signed contract)

**Status:** Template for Legal review. Not legal advice.

1. **Parties** — Controller (customer) / Processor (heald operator)
2. **Subject** — Optional fleet telemetry; default bank mode = **no processing** (cloud off)
3. **Categories** — Hostname, hardware UUID, metrics, activity event summaries (PII-redacted when outbound)
4. **Location** — EU processing only if cloud enabled; on-device AI never leaves device
5. **Subprocessors** — List hosting (e.g. Vercel / DB host) only if cloud on
6. **Security** — Device tokens, TLS, least privilege, audit logs
7. **Retention** — Customer-controlled local `~/.heald`; cloud retention policy TBD
8. **Deletion** — Uninstall + `HEALD_PURGE_DATA=1`; cloud delete API TBD
9. **Audit rights** — Annual questionnaire / pen-test report on request
10. **Exit** — Export compliance JSON + activity NDJSON; 30-day wind-down

**Bank pilot default:** No personal data leaves the Mac → DPA scope minimal until cloud enabled.
