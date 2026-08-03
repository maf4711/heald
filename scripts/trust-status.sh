#!/usr/bin/env bash
# P0.1 / P0.2 status: codesign identities + binary signature
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/.build/release/heald}"

echo "=== Codesigning identities ==="
security find-identity -v -p codesigning 2>&1 || true
echo ""
echo "=== Developer ID Application present? ==="
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  echo "YES — notarization path available"
  HAS_DEVID=1
else
  echo "NO — only Development/Distribution found"
  echo "    Bank Gatekeeper path needs: Developer ID Application (+ notary credentials)"
  HAS_DEVID=0
fi
echo ""
echo "=== Binary: $BIN ==="
if [[ -f "$BIN" ]]; then
  codesign -dv --verbose=2 "$BIN" 2>&1 | head -20 || echo "(unsigned / adhoc)"
  file "$BIN"
else
  echo "missing — run swift build -c release"
fi
echo ""
echo "=== Env for notarize.sh ==="
echo "APPLE_ID=${APPLE_ID:+set}"
echo "APPLE_TEAM_ID=${APPLE_TEAM_ID:+set}"
echo "APPLE_APP_SPECIFIC_PASSWORD=${APPLE_APP_SPECIFIC_PASSWORD:+set}"
echo "CODESIGN_IDENTITY=${CODESIGN_IDENTITY:-unset}"
echo ""
if [[ "$HAS_DEVID" -eq 1 ]]; then
  echo "Next: CODESIGN_IDENTITY='Developer ID Application: …' ./scripts/notarize.sh $BIN"
else
  echo "Next: Create Developer ID cert in Apple Developer portal (not App Store Distribution)."
fi
