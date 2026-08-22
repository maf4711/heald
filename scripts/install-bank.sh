#!/usr/bin/env bash
# Bank-mode local install (P0/P1). No cloud, no auto-update, bank policy.
# Usage: ./scripts/install-bank.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.heald.daemon"
INSTALL_DIR="${HOME}/Library/heald"
BINARY="${INSTALL_DIR}/heald"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
USER_ID="$(id -u)"
SRC="${ROOT}/.build/release/heald"

echo "==> heald bank install"

if [[ ! -x "$SRC" ]]; then
  echo "==> building release..."
  (cd "$ROOT" && swift build -c release)
fi

mkdir -p "$INSTALL_DIR" "${HOME}/Library/LaunchAgents"
# Stop existing
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
pkill -x heald 2>/dev/null || true
sleep 1

cp -f "$SRC" "$BINARY"
chmod 755 "$BINARY"
codesign --force --sign - "$BINARY" >/dev/null 2>&1 || true

# Plist from bank template
BIN_ESC="$BINARY"
sed "s|__HEALD_BINARY__|${BIN_ESC}|g" \
  "$ROOT/launchd/com.heald.daemon.bank.plist" > "$PLIST"
chmod 644 "$PLIST"
plutil -lint "$PLIST" >/dev/null

# Bank policy + enroll (always enforce bank on this install path)
"$BINARY" policy --preset bank
"$BINARY" enroll 2>/dev/null || "$BINARY" enroll --force

launchctl bootstrap "gui/${USER_ID}" "$PLIST" 2>/dev/null \
  || launchctl kickstart -k "gui/${USER_ID}/${LABEL}" 2>/dev/null \
  || true
sleep 2

echo ""
"$BINARY" doctor
echo ""
echo "OK bank install: $BINARY"
echo "Uninstall: ${ROOT}/uninstall.sh"
