#!/usr/bin/env bash
set -euo pipefail

# heald install script
# Usage: ./install.sh
# Do NOT run with sudo — Homebrew refuses root execution.

LABEL="com.heald.daemon"
INSTALL_DIR="$HOME/Library/heald"
BINARY="$INSTALL_DIR/heald"
PLIST_TEMPLATE="$(cd "$(dirname "$0")" && pwd)/launchd/${LABEL}.plist"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
USER_ID=$(id -u)

# Guard: refuse root execution (Homebrew blocks it, fail early with a clear message)
if [ "$EUID" -eq 0 ]; then
    echo "Error: Do not run install.sh as root (sudo). Homebrew refuses root execution."
    echo "Run as your regular user: ./install.sh"
    exit 1
fi

echo "==> Installing heald..."

# 1. Homebrew — install if missing, add to PATH for Apple Silicon
if ! command -v brew &>/dev/null; then
    echo "==> Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# Ensure brew is on PATH for both Intel (/usr/local) and Apple Silicon (/opt/homebrew)
if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# 2. Install Ollama CLI formula (not the GUI cask)
# Note: Ollama will be used by Phase 7 AI integration; installed here per DAEM-04.
if ! brew list ollama &>/dev/null; then
    echo "==> Installing ollama via Homebrew..."
    brew install ollama
else
    echo "==> ollama already installed — skipping"
fi

# 3. Build heald release binary
echo "==> Building heald (release)..."
# Run swift build from the script's directory (the package root)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
swift build -c release

# 4. Install binary
echo "==> Installing binary to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp ".build/release/heald" "$BINARY"
chmod 755 "$BINARY"

# 5. Install plist (substitute USERNAME placeholder with actual username)
echo "==> Installing LaunchAgent plist..."
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|USERNAME|$(whoami)|g" "$PLIST_TEMPLATE" > "$PLIST"
chmod 644 "$PLIST"

# 6. Validate plist before bootstrapping (catches XML errors before silent launchd failure)
plutil -lint "$PLIST"

# 7. Bootstrap LaunchAgent (bootout first to handle re-install gracefully)
echo "==> Loading LaunchAgent..."
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${USER_ID}" "$PLIST"

echo ""
echo "heald installed successfully."
echo "Verify: launchctl list | grep heald"
echo "Logs:   log stream --predicate 'subsystem==\"com.heald.daemon\"' --level info"
