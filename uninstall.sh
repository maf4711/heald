#!/usr/bin/env bash
set -euo pipefail

# heald uninstall script
# Usage: ./uninstall.sh
# Removes the LaunchAgent, stops the daemon, and deletes all installed files.
# Does NOT uninstall Homebrew packages (ollama may be used independently).

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

echo ""
echo "heald uninstalled."
echo "Note: ollama was not removed (it may be used independently)."
echo "To remove ollama: brew uninstall ollama"
