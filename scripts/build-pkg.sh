#!/usr/bin/env bash
# Build a simple component pkg for Jamf / internal distro (unsigned unless IDENTITY set).
# Usage: ./scripts/build-pkg.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${HEALD_VERSION:-$(./.build/release/heald --version 2>/dev/null || echo 3.2.0)}"
STAGE="$(mktemp -d -t heald-pkg)"
PKG_ROOT="$STAGE/root"
SCRIPTS="$STAGE/scripts"
OUT="$ROOT/dist/heald-${VERSION}.pkg"

echo "==> build release"
swift build -c release

echo "==> stage payload"
mkdir -p "$PKG_ROOT/usr/local/heald" "$PKG_ROOT/Library/LaunchAgents" "$SCRIPTS" "$ROOT/dist"
cp .build/release/heald "$PKG_ROOT/usr/local/heald/heald"
chmod 755 "$PKG_ROOT/usr/local/heald/heald"

# LaunchAgent template — install script rewrites path if needed
cat > "$PKG_ROOT/Library/LaunchAgents/com.heald.daemon.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.heald.daemon</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/heald/heald</string>
    <string>run</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HEALD_CLOUD</key><string>0</string>
  </dict>
  <key>StandardOutPath</key><string>/tmp/heald.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/heald.err.log</string>
</dict>
</plist>
PLIST

cat > "$SCRIPTS/postinstall" <<'POST'
#!/bin/bash
set -e
USER_ID=$(stat -f %u /dev/console 2>/dev/null || echo 0)
# Prefer per-user install for non-root lab; Jamf often uses system context.
if [[ "$USER_ID" -gt 0 ]]; then
  HOME_DIR=$(dscl . -read "/Users/$(id -un "$USER_ID" 2>/dev/null)" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  if [[ -n "$HOME_DIR" ]]; then
    mkdir -p "$HOME_DIR/Library/heald"
    cp /usr/local/heald/heald "$HOME_DIR/Library/heald/heald"
    chmod 755 "$HOME_DIR/Library/heald/heald"
    # Bank preset on first install if no policy
    if [[ ! -f "$HOME_DIR/.heald/policy.json" ]]; then
      sudo -u "#$USER_ID" /usr/local/heald/heald policy --preset bank 2>/dev/null || true
    fi
    sudo -u "#$USER_ID" /usr/local/heald/heald enroll 2>/dev/null || true
  fi
fi
exit 0
POST
chmod 755 "$SCRIPTS/postinstall"

echo "==> pkgbuild"
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$SCRIPTS" \
  --identifier "sh.heald.daemon" \
  --version "$VERSION" \
  --install-location "/" \
  "$OUT"

echo "Package: $OUT"
echo "Sign (optional): productsign --sign 'Developer ID Installer' $OUT $OUT.signed"
rm -rf "$STAGE"
