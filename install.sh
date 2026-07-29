#!/usr/bin/env bash
set -euo pipefail

# heald installer — one command, no Xcode required
# curl -sL https://raw.githubusercontent.com/maf4711/heald/main/install.sh | bash

LABEL="com.heald.daemon"
INSTALL_DIR="$HOME/Library/heald"
BINARY="$INSTALL_DIR/heald"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
USER_ID=$(id -u)
USERNAME=$(whoami)
HOSTNAME_SHORT=$(hostname -s)
API_KEY="REDACTED"
API_URL="https://heald.merados.com/api/ingest"
DASHBOARD="https://heald.merados.com"
RELEASE_URL="https://github.com/maf4711/heald/releases/latest/download/heald"

B="\033[1m" G="\033[32m" Y="\033[33m" C="\033[36m" D="\033[2m" R="\033[0m"

step() { echo -e "\n${B}[$1/5]${R} $2"; }
ok()   { echo -e "  ${G}OK${R} $1"; }
warn() { echo -e "  ${Y}!!${R} $1"; }

echo ""
echo -e "${B}heald${R} installer — ${C}${HOSTNAME_SHORT}${R} (${USERNAME})"
echo -e "${D}Self-healing macOS daemon with fleet dashboard${R}"

# ── 1. Download binary ────────────────────────────────────
step 1 "Binary"
mkdir -p "$INSTALL_DIR"

NEED_DOWNLOAD=true
if [ -f "$BINARY" ]; then
    SIZE=$(stat -f%z "$BINARY" 2>/dev/null || echo "0")
    if [ "$SIZE" -gt 1000000 ]; then
        ok "already installed ($(du -h "$BINARY" | cut -f1))"
        NEED_DOWNLOAD=false
    fi
fi

if $NEED_DOWNLOAD; then
    # Check Homebrew first
    BREW_BIN=""
    if command -v brew &>/dev/null; then
        BREW_BIN="$(brew --prefix heald 2>/dev/null)/bin/heald" 2>/dev/null || true
    fi

    if [ -n "$BREW_BIN" ] && [ -f "$BREW_BIN" ]; then
        cp "$BREW_BIN" "$BINARY"
        ok "copied from Homebrew"
    else
        echo -e "  Downloading from GitHub..."
        curl -L --progress-bar "$RELEASE_URL" -o "$BINARY"
        ok "downloaded ($(du -h "$BINARY" | cut -f1))"
    fi
fi
chmod 755 "$BINARY"

# Verify it's a real binary (not an HTML error page)
if ! file "$BINARY" | grep -q "Mach-O"; then
    echo -e "  \033[31mError: not a valid macOS binary\033[0m"
    file "$BINARY"
    rm -f "$BINARY"
    exit 1
fi

# ── 2. LaunchAgent ────────────────────────────────────────
step 2 "LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${BINARY}</string>
        <string>run</string>
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
ok "$PLIST"

# ── 3. Start daemon ──────────────────────────────────────
step 3 "Daemon"
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
kill $(pgrep -x heald 2>/dev/null) 2>/dev/null || true
sleep 2
launchctl bootstrap "gui/${USER_ID}" "$PLIST" 2>/dev/null || true
sleep 3

PID=$(pgrep -x heald 2>/dev/null | head -1 || true)
if [ -n "$PID" ]; then
    ok "running (PID: $PID)"
else
    warn "not started — trying direct launch..."
    "$BINARY" &>/dev/null &
    disown
    sleep 3
    PID=$(pgrep -x heald 2>/dev/null | head -1 || true)
    if [ -n "$PID" ]; then
        ok "running (PID: $PID)"
    else
        warn "check /tmp/heald.err.log"
    fi
fi

# ── 4. Verify dashboard push ─────────────────────────────
step 4 "Dashboard"
echo -e "  Waiting for first push..."
FOUND=false
for i in $(seq 1 6); do
    RESULT=$(curl -sf "${DASHBOARD}/api/machines" 2>/dev/null | python3 -c "
import json,sys
try:
    ms=json.load(sys.stdin).get('machines',[])
    for m in ms:
        if '${HOSTNAME_SHORT}' in m.get('machineId','') or '${HOSTNAME_SHORT}' in m.get('hostname',''):
            print('FOUND')
except: pass
" 2>/dev/null || true)
    if [ "$RESULT" = "FOUND" ]; then
        FOUND=true
        break
    fi
    sleep 5
done

if $FOUND; then
    ok "${HOSTNAME_SHORT} visible on dashboard"
else
    warn "not visible yet (may take up to 30s)"
fi

# ── 5. System info ────────────────────────────────────────
step 5 "This machine"
echo -e "  ${C}${HOSTNAME_SHORT}${R}"
echo -e "  Model:    $(sysctl -n hw.model 2>/dev/null || echo '?')"
echo -e "  macOS:    $(sw_vers -productVersion 2>/dev/null || echo '?')"
echo -e "  CPU:      $(sysctl -n machdep.cpu.brand_string 2>/dev/null | sed 's/  */ /g' || echo '?')"
echo -e "  RAM:      $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1073741824}' || echo '?')"
echo -e "  Disk:     $(df -h / 2>/dev/null | tail -1 | awk '{print $3 " used / " $2 " total (" $5 ")"}')"

# iCloud status
ICLOUD_DOMAIN=$(xattr -p com.apple.file-provider-domain-id ~/Documents 2>/dev/null || echo "")
if [ -n "$ICLOUD_DOMAIN" ]; then
    LOCAL=$(find ~/Documents -maxdepth 3 -type f ! -name '.DS_Store' ! -name '.*.icloud' 2>/dev/null | wc -l | tr -d ' ')
    CLOUD=$(find ~/Documents -maxdepth 3 -name '.*.icloud' 2>/dev/null | wc -l | tr -d ' ')
    TOTAL=$((LOCAL + CLOUD))
    PCT=100; [ "$TOTAL" -gt 0 ] && PCT=$((LOCAL * 100 / TOTAL))
    BIRD=$(pgrep -x bird >/dev/null 2>&1 && echo "running" || echo "DOWN")
    echo -e "  iCloud:   ${G}enabled${R} — ${LOCAL} local, ${CLOUD} cloud (${PCT}% sync) — bird ${BIRD}"
else
    echo -e "  iCloud:   ${Y}not enabled${R}"
fi

# ── Done ──────────────────────────────────────────────────
echo ""
echo -e "${B}Done.${R} heald is monitoring ${C}${HOSTNAME_SHORT}${R}."
echo ""
echo -e "  ${G}Dashboard${R}  ${DASHBOARD}"
echo -e "  ${G}Logs${R}       tail -f /tmp/heald.err.log"
echo ""
