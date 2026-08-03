#!/usr/bin/env bash
# Print version + sha256 for dashboard client-release / GitHub release notes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/.build/release/heald}"
if [[ ! -f "$BIN" ]]; then
  echo "Build first: swift build -c release" >&2
  exit 1
fi
VER=$("$BIN" --version 2>/dev/null | head -1 | tr -d '[:space:]')
SHA=$(shasum -a 256 "$BIN" | awk '{print $1}')
SIZE=$(stat -f%z "$BIN" 2>/dev/null || stat -c%s "$BIN")
echo "version=$VER"
echo "sha256=$SHA"
echo "size=$SIZE"
echo "path=$BIN"
echo ""
echo "dashboard/src/lib/client-release.ts snippet:"
echo "  version: \"$VER\","
echo "  sha256: \"$SHA\","
