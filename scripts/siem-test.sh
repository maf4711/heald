#!/usr/bin/env bash
# P3.b helper: print SIEM config; optional local UDP listen check
set -euo pipefail
echo "HEALD_SIEM_HOST=${HEALD_SIEM_HOST:-}"
echo "HEALD_SIEM_PORT=${HEALD_SIEM_PORT:-514}"
if command -v heald >/dev/null; then
  heald policy 2>/dev/null | grep -i siem || true
fi
if [[ "${1:-}" == "--listen" ]]; then
  PORT="${HEALD_SIEM_PORT:-5140}"
  echo "Listening UDP $PORT (nc) — set HEALD_SIEM_HOST=127.0.0.1 HEALD_SIEM_PORT=$PORT and restart daemon"
  nc -u -l "$PORT" || true
fi
