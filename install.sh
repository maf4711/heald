#!/usr/bin/env bash
set -euo pipefail

# heald install script — binary distribution (no Xcode required)
# Usage: bash install.sh
#        bash $(brew --prefix heald)/install.sh

LABEL="com.heald.daemon"
INSTALL_DIR="$HOME/Library/heald"
BINARY="$INSTALL_DIR/heald"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
USER_ID=$(id -u)
API_KEY="REDACTED"
API_URL="https://heald.merados.com/api/ingest"
RELEASE_URL="https://github.com/maf4711/heald/releases/latest/download/heald"

BOLD="\033[1m"
GREEN="\033[32m"
DIM="\033[2m"
RESET="\033[0m"

echo -e "${BOLD}heald installer${RESET}"
echo ""

# ── 1. Get binary ─────────────────────────────────────────
mkdir -p "$INSTALL_DIR"

# Check if installed via Homebrew
BREW_BIN=""
if command -v brew &>/dev/null; then
    BREW_BIN="$(brew --prefix heald 2>/dev/null)/bin/heald" || true
fi

if [ -n "$BREW_BIN" ] && [ -f "$BREW_BIN" ]; then
    echo -e "  ${GREEN}Binary from Homebrew${RESET}"
    cp "$BREW_BIN" "$BINARY"
elif [ -f "$BINARY" ] && "$BINARY" --version &>/dev/null; then
    echo -e "  ${GREEN}Binary already installed${RESET}"
else
    echo -e "  Downloading binary..."
    curl -sL "$RELEASE_URL" -o "$BINARY"
fi
chmod 755 "$BINARY"

# Verify it runs
if ! "$BINARY" --version &>/dev/null; then
    echo "Error: binary does not execute. Wrong architecture?"
    file "$BINARY"
    exit 1
fi
echo -e "  ${GREEN}Binary OK${RESET}: $BINARY"

# ── 2. Install LaunchAgent plist ──────────────────────────
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY}</string>
    </array>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
    <key>LowPriorityIO</key>
    <true/>
    <key>Nice</key>
    <integer>5</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HEALD_API_KEY</key>
        <string>${API_KEY}</string>
        <key>HEALD_API_URL</key>
        <string>${API_URL}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>/tmp/heald.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/heald.err.log</string>
</dict>
</plist>
PLISTEOF

chmod 644 "$PLIST"
plutil -lint "$PLIST" >/dev/null
echo -e "  ${GREEN}LaunchAgent OK${RESET}: $PLIST"

# ── 3. Start daemon ───────────────────────────────────────
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
kill $(pgrep -x heald) 2>/dev/null || true
sleep 2
launchctl bootstrap "gui/${USER_ID}" "$PLIST"
sleep 3

PID=$(pgrep -x heald | head -1 || true)
if [ -n "$PID" ]; then
    echo -e "  ${GREEN}Daemon running${RESET} (PID: $PID)"
else
    echo "  Warning: daemon not running yet (check /tmp/heald.err.log)"
fi

# ── 4. Ollama (optional, non-blocking) ───────────────────
if command -v ollama &>/dev/null; then
    echo -e "  ${DIM}Ollama found — pulling model in background...${RESET}"
    (ollama pull qwen3-coder:30b &>/dev/null &) || true
else
    echo -e "  ${DIM}Ollama not installed (optional, for AI features)${RESET}"
fi

# ── Done ──────────────────────────────────────────────────
echo ""
echo -e "${BOLD}heald installed.${RESET}"
echo ""
echo -e "  Dashboard:  ${GREEN}https://heald.merados.com${RESET}"
echo -e "  Terminal:   ${GREEN}heald-top${RESET}"
echo -e "  Logs:       log stream --predicate 'subsystem==\"com.heald.daemon\"' --level info"
echo -e "  Uninstall:  launchctl bootout gui/\$(id -u)/com.heald.daemon"
echo ""
