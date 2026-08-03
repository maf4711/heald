#!/usr/bin/env bash
# Build component pkg for bank / Jamf (P0.3–P0.4).
# Usage: ./scripts/build-pkg.sh
# Optional: CODESIGN_IDENTITY="Developer ID Application: …" to codesign binary before pack.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> build release"
swift build -c release
VERSION="${HEALD_VERSION:-$(./.build/release/heald --version 2>/dev/null | head -1 | tr -d '[:space:]' || echo 3.3.0)}"
STAGE="$(mktemp -d -t heald-pkg)"
PKG_ROOT="$STAGE/root"
SCRIPTS="$STAGE/scripts"
OUT="$ROOT/dist/heald-${VERSION}.pkg"
BIN_SRC="$ROOT/.build/release/heald"

mkdir -p "$PKG_ROOT/usr/local/heald" \
  "$PKG_ROOT/Library/Application Support/heald" \
  "$SCRIPTS" "$ROOT/dist"

cp "$BIN_SRC" "$PKG_ROOT/usr/local/heald/heald"
chmod 755 "$PKG_ROOT/usr/local/heald/heald"

# Bank LaunchAgent template (system path; postinstall also copies per-user)
cp "$ROOT/launchd/com.heald.daemon.bank.plist" \
  "$PKG_ROOT/Library/Application Support/heald/com.heald.daemon.bank.plist"
# Fix placeholder for system binary
sed -i '' 's|__HEALD_BINARY__|/usr/local/heald/heald|g' \
  "$PKG_ROOT/Library/Application Support/heald/com.heald.daemon.bank.plist" 2>/dev/null \
  || sed -i 's|__HEALD_BINARY__|/usr/local/heald/heald|g' \
  "$PKG_ROOT/Library/Application Support/heald/com.heald.daemon.bank.plist"

# Optional codesign
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> codesign with $CODESIGN_IDENTITY"
  codesign --force --options runtime --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    --identifier "sh.heald.daemon" \
    "$PKG_ROOT/usr/local/heald/heald"
  codesign --verify --verbose=2 "$PKG_ROOT/usr/local/heald/heald" || true
else
  echo "==> no CODESIGN_IDENTITY — packing unsigned (lab/internal only)"
  echo "    For Gatekeeper: export CODESIGN_IDENTITY='Developer ID Application: …'"
fi

cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/bash
set -euo pipefail
SYS_BIN="/usr/local/heald/heald"
TEMPLATE="/Library/Application Support/heald/com.heald.daemon.bank.plist"
LABEL="com.heald.daemon"

# Console user (Jamf / GUI)
USER_ID=$(stat -f %u /dev/console 2>/dev/null || echo "0")
if [[ "$USER_ID" -le 0 ]]; then
  exit 0
fi
USERNAME=$(id -un "$USER_ID" 2>/dev/null || true)
HOME_DIR=$(dscl . -read "/Users/${USERNAME}" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
[[ -z "$HOME_DIR" || ! -d "$HOME_DIR" ]] && exit 0

USER_BIN="${HOME_DIR}/Library/heald/heald"
USER_PLIST="${HOME_DIR}/Library/LaunchAgents/${LABEL}.plist"

mkdir -p "${HOME_DIR}/Library/heald" "${HOME_DIR}/Library/LaunchAgents"
cp -f "$SYS_BIN" "$USER_BIN"
chmod 755 "$USER_BIN"
chown "${USER_ID}:staff" "$USER_BIN" 2>/dev/null || true

# Per-user bank plist
if [[ -f "$TEMPLATE" ]]; then
  sed "s|/usr/local/heald/heald|${USER_BIN}|g" "$TEMPLATE" > "$USER_PLIST"
else
  # fallback minimal
  cat > "$USER_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array>
    <string>${USER_BIN}</string><string>run</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>EnvironmentVariables</key><dict>
    <key>HEALD_CLOUD</key><string>0</string>
    <key>HEALD_AUTO_UPDATE</key><string>1</string>
    <key>HEALD_UPDATE_INTERVAL_SEC</key><string>1800</string>
  </dict>
  <key>StandardOutPath</key><string>/tmp/heald.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/heald.err.log</string>
</dict></plist>
EOF
fi
chown "${USER_ID}:staff" "$USER_PLIST" 2>/dev/null || true
chmod 644 "$USER_PLIST"

# Always bank policy + enroll for bank pkg
sudo -u "#${USER_ID}" "$USER_BIN" policy --preset bank 2>/dev/null || true
sudo -u "#${USER_ID}" "$USER_BIN" enroll 2>/dev/null || true

# Load agent
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${USER_ID}" "$USER_PLIST" 2>/dev/null || true
exit 0
POST
chmod 755 "$SCRIPTS/postinstall"

echo "==> pkgbuild → $OUT"
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$SCRIPTS" \
  --identifier "sh.heald.daemon" \
  --version "$VERSION" \
  --install-location "/" \
  "$OUT"

# Optional productsign
if [[ -n "${INSTALLER_IDENTITY:-}" ]]; then
  SIGNED="${OUT%.pkg}-signed.pkg"
  productsign --sign "$INSTALLER_IDENTITY" "$OUT" "$SIGNED"
  echo "Signed pkg: $SIGNED"
fi

echo "Package: $OUT"
ls -lh "$OUT"
rm -rf "$STAGE"
