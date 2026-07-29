#!/usr/bin/env bash
set -euo pipefail

# heald uninstall script
# Usage: ./uninstall.sh
# Removes the LaunchAgent, stops the daemon, and deletes all installed files.
# Does not remove ~/.heald data (metrics/activity) unless HEALD_PURGE_DATA=1.

LABEL="com.heald.daemon"
INSTALL_DIR="$HOME/Library/heald"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
USER_ID=$(id -u)

echo "==> Uninstalling heald..."

# 1. Stop and unload LaunchAgent (bootout is idempotent with || true)
if launchctl list "$LABEL" &>/dev/null 2>&1; then
    echo "==> Stopping daemon..."
    launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
else
    echo "==> Daemon not running — skipping bootout"
fi

# 2. Remove plist
if [ -f "$PLIST" ]; then
    echo "==> Removing LaunchAgent plist..."
    rm -f "$PLIST"
else
    echo "==> Plist not found — skipping"
fi

# 3. Remove binary and install directory
if [ -d "$INSTALL_DIR" ]; then
    echo "==> Removing $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
else
    echo "==> Install directory not found — skipping"
fi

if [ "${HEALD_PURGE_DATA:-0}" = "1" ]; then
    echo "==> Purging ~/.heald data..."
    rm -rf "$HOME/.heald"
fi

echo ""
echo "heald uninstalled."
echo "AI was on-device Apple Intelligence only — nothing else to remove."
echo "Data left in ~/.heald (set HEALD_PURGE_DATA=1 to delete)."
