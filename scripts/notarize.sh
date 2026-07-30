#!/usr/bin/env bash
# Notarization scaffold — requires Apple Developer ID Application cert + notary credentials.
# Usage:
#   export APPLE_ID=... APPLE_TEAM_ID=... APPLE_APP_SPECIFIC_PASSWORD=...
#   ./scripts/notarize.sh .build/release/heald
set -euo pipefail

BIN="${1:-.build/release/heald}"
IDENTITY="${CODESIGN_IDENTITY:-Developer ID Application}"
BUNDLE_ID="${HEALD_BUNDLE_ID:-sh.heald.daemon}"

if [[ ! -f "$BIN" ]]; then
  echo "Binary not found: $BIN" >&2
  echo "Build first: swift build -c release" >&2
  exit 1
fi

echo "==> codesign (adhoc if no Developer ID)"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
  codesign --force --options runtime --timestamp \
    --sign "Developer ID Application" \
    --identifier "$BUNDLE_ID" \
    "$BIN"
  codesign --verify --verbose=2 "$BIN"
else
  echo "!! No Developer ID Application cert — adhoc sign only (not bank-ready)"
  codesign --force --sign - "$BIN" || true
  echo "Install a Developer ID cert, then re-run this script."
  exit 2
fi

if [[ -z "${APPLE_ID:-}" || -z "${APPLE_TEAM_ID:-}" || -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "!! Notary credentials missing (APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD)"
  echo "   Binary is signed but not notarized."
  exit 3
fi

ZIP="$(mktemp -t heald).zip"
ditto -c -k --keepParent "$BIN" "$ZIP"
echo "==> notarytool submit"
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait
rm -f "$ZIP"
echo "==> staple (if applicable for pkg/app; bare bin often skip)"
echo "Done. Ship via scripts/build-pkg.sh for distribution."
