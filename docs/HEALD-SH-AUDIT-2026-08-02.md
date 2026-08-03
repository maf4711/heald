# heald.sh Audit Report — 2026-08-02

## Scope

End-to-end check of **heald.sh** fleet dashboard (project `heald`) and related domains (`www.heald.sh`, `heald.care`, `marco.heald.sh`). Fixes applied and re-deployed the same day.

## Mapping (target state)

| Domain | Project | Role |
|--------|---------|------|
| `heald.sh` | **heald** | Fleet Health Dashboard |
| `www.heald.sh` | **heald** | Same app |
| `heald.care` | **heald-care** | Marco Befunde (separate product) |
| `www.heald.care` | **heald-care** | Same |
| `marco.heald.sh` | *(none)* | Decoupled (404) |

## Findings (before fix)

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| F1 | High | Vercel DNS for `heald.sh` still pointed at legacy A `76.76.21.21` (verify: “DNS Change Recommended”) | **Fixed** |
| F2 | Medium | `www` CNAME used generic `cname.vercel-dns.com` instead of project-specific target | **Fixed** |
| F3 | Medium | `/api/health` missing (404) — no public liveness endpoint | **Fixed** |
| F4 | Low | `/robots.txt` and `/sitemap.xml` missing | **Fixed** |
| F5 | Low | No favicon / Open Graph metadata | **Fixed** (icon + OG; favicon redirect) |
| F6 | Medium | `marco.heald.sh` had been re-attached to `heald-care` with redirect to `heald.care` after earlier decouple | **Fixed** (removed again → 404) |
| F7 | Info | HTTP→HTTPS 308 works | OK |
| F8 | Info | Static JS chunks 200 | OK |
| F9 | Info | `/api/update` public manifest 200 (v3.5.0) | OK |

## Fixes applied

### Infrastructure (Vercel DNS + domains)

1. Removed apex A `76.76.21.21`
2. Added apex A **`216.150.1.1`** and **`216.150.16.1`**
3. Set `www` CNAME → **`a2246ae4ad294a0f.vercel-dns-017.com.`**
4. Removed `marco.heald.sh` from project `heald-care`

### Application (`dashboard/`, deployed prod)

| Path | Change |
|------|--------|
| `src/app/api/health/route.ts` | New liveness JSON |
| `src/app/robots.ts` | Allow public routes; disallow private APIs |
| `src/app/sitemap.ts` | Sitemap for apex + update |
| `src/app/icon.tsx` | Generated tab icon |
| `src/app/layout.tsx` | `metadataBase`, Open Graph, Twitter, canonical |
| `next.config.ts` | `/favicon.ico` → `/icon` redirect |

Production deploy aliased to **https://heald.sh** (Ready).

## Post-fix verification

| URL | Result |
|-----|--------|
| https://heald.sh/ | **200** — Fleet Health Dashboard |
| https://www.heald.sh/ | **200** |
| https://heald.sh/api/health | **200** `{"ok":true,"service":"heald",...}` |
| https://heald.sh/api/update | **200** client release manifest |
| https://heald.sh/robots.txt | **200** |
| https://heald.sh/sitemap.xml | **200** |
| https://heald.sh/icon | **200** PNG |
| https://heald.sh/favicon.ico | redirect → icon (after redeploy) |
| Vercel verify `heald.sh` | **Valid Configuration** · project heald |
| Vercel verify `www.heald.sh` | **Valid Configuration** · project heald |
| DNS apex @1.1.1.1 | `216.150.1.1` `216.150.16.1` |
| https://heald.care/ | **200** (separate product) |
| https://marco.heald.sh/ | **404** DEPLOYMENT_NOT_FOUND (intended) |

## Residual / follow-ups (non-blocking)

1. **npm audit** on dashboard deps reports high issues (Next/transitive) — consider planned upgrade, not a domain outage.
2. **www → apex redirect** optional (both serve the same app today).
3. **heald.care** is a different product (`heald-care`); not part of fleet dashboard code path.
4. Commit local dashboard changes to git if not already on the deployed branch (Vercel CLI deployed working tree).

## Conclusion

**heald.sh is live and correctly mapped to project `heald`.** DNS matches Vercel recommendations, public health/SEO endpoints exist, and the wrong subdomain attachment (`marco.heald.sh`) is cleared again.
