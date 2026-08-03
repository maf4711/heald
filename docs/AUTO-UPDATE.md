# Client Auto-Distribution

When a new heald binary is published, **installed daemons pull it themselves**.

## Flow

```
Developer
  ./scripts/publish-client.sh
       │
       ├─► GitHub Release asset `heald`
       └─► heald.sh /api/update  { version, url, sha256 }
                    ▲
                    │ poll ~30 min
              heald daemon (managed install)
                    │
                    ├─ download + verify SHA-256 + Mach-O
                    ├─ replace ~/Library/heald/heald
                    └─ exit → launchd KeepAlive restarts new binary
```

## Client control

| Control | Effect |
|---------|--------|
| default | **ON** for managed install (`~/Library/heald/heald`) |
| `HEALD_AUTO_UPDATE=0` | Off (LaunchAgent env) |
| `heald policy --auto-update-off` | Off via policy |
| `heald policy --auto-update-on` | On |
| `HEALD_UPDATE_INTERVAL_SEC` | Poll seconds (min 60, default 1800) |
| `HEALD_UPDATE_URL` | Override manifest URL |

## Publish (server side)

```bash
./scripts/publish-client.sh
# or without deploy:
./scripts/publish-client.sh --no-deploy
```

Requires: `gh` auth for GitHub release; Vercel for dashboard deploy.

## Manual

```bash
heald update --check   # compare versions
heald update           # install if newer
heald doctor           # shows Auto-update + last status
```

Status file: `~/.heald/data/auto_update.json`

## Security

- HTTPS only  
- Optional SHA-256 from manifest (required for production releases)  
- Only replaces managed path `~/Library/heald/heald`  
- Bank mode can keep cloud metrics off while still updating the binary  
