#!/usr/bin/env bash
# Publish a new heald client for fleet auto-distribution.
#
# 1) Build release binary
# 2) Compute sha256
# 3) Update dashboard/src/lib/client-release.ts
# 4) Optional: upload to GitHub Releases (needs `gh` + auth)
# 5) Deploy dashboard so /api/update serves the new manifest
#
# Usage:
#   ./scripts/publish-client.sh
#   ./scripts/publish-client.sh --no-deploy
#   ./scripts/publish-client.sh --no-github
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DO_DEPLOY=1
DO_GITHUB=1
for a in "$@"; do
  case "$a" in
    --no-deploy) DO_DEPLOY=0 ;;
    --no-github) DO_GITHUB=0 ;;
  esac
done

echo "==> build"
swift build -c release
BIN="$ROOT/.build/release/heald"
VER=$("$BIN" --version 2>/dev/null | head -1 | tr -d '[:space:]')
SHA=$(shasum -a 256 "$BIN" | awk '{print $1}')
SIZE=$(stat -f%z "$BIN" 2>/dev/null || stat -c%s "$BIN")
echo "    version=$VER"
echo "    sha256=$SHA"
echo "    size=$SIZE"

mkdir -p "$ROOT/dist"
cp -f "$BIN" "$ROOT/dist/heald"
cp -f "$BIN" "$ROOT/dist/heald-$VER"

RELEASE_URL="https://github.com/maf4711/heald/releases/download/v${VER}/heald"
NOTES="heald ${VER} — fleet auto-update"

echo "==> client-release.ts"
python3 - <<PY
from pathlib import Path
p = Path("dashboard/src/lib/client-release.ts")
text = p.read_text()
import re
def sub_field(name, value, text):
    # version: "x",
    pat = rf'({name}:\s*")[^"]*(")'
    return re.sub(pat, rf'\g<1>{value}\g<2>', text, count=1)
text = sub_field("version", "$VER", text)
text = sub_field("url", "$RELEASE_URL", text)
text = sub_field("sha256", "$SHA", text)
text = sub_field("notes", "$NOTES", text)
p.write_text(text)
print("updated", p)
PY

if [[ "$DO_GITHUB" -eq 1 ]]; then
  if command -v gh >/dev/null 2>&1; then
    echo "==> GitHub release v$VER"
    if gh release view "v$VER" >/dev/null 2>&1; then
      gh release upload "v$VER" "$ROOT/dist/heald-$VER" --clobber \
        || gh release upload "v$VER" "$BIN" --clobber
      # ensure asset name is `heald`
      gh release upload "v$VER" "$ROOT/dist/heald#heald" --clobber 2>/dev/null || true
    else
      gh release create "v$VER" "$ROOT/dist/heald#heald" \
        --title "heald $VER" \
        --notes "$NOTES" \
        || {
          echo "!! gh release create failed — upload binary manually to $RELEASE_URL"
        }
    fi
  else
    echo "!! gh not installed — skip GitHub upload"
    echo "   put binary at: $RELEASE_URL"
  fi
fi

if [[ "$DO_DEPLOY" -eq 1 ]]; then
  if [[ -x "$ROOT/scripts/deploy-dashboard.sh" ]]; then
    echo "==> deploy dashboard (manifest live)"
    "$ROOT/scripts/deploy-dashboard.sh" || echo "!! deploy failed — run manually"
  else
    echo "!! no deploy-dashboard.sh"
  fi
fi

echo ""
echo "=== Publish complete ==="
echo "Manifest: https://heald.sh/api/update"
echo "Clients poll every ~30 min (HEALD_UPDATE_INTERVAL_SEC)."
echo "Force now:  heald update"
echo "Verify:     curl -sS https://heald.sh/api/update | python3 -m json.tool"
