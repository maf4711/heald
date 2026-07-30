#!/usr/bin/env bash
# Generate SBOM if syft is installed (CycloneDX JSON).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist/heald.sbom.cdx.json}"
mkdir -p "$(dirname "$OUT")"
if command -v syft >/dev/null 2>&1; then
  syft "$ROOT" -o cyclonedx-json > "$OUT"
  echo "SBOM: $OUT"
else
  echo "syft not found — install: brew install syft" >&2
  echo "Writing minimal stub SBOM"
  cat > "$OUT" <<EOF
{
  "bomFormat": "CycloneDX",
  "specVersion": "1.5",
  "version": 1,
  "metadata": {
    "component": {
      "type": "application",
      "name": "heald",
      "version": "3.2.0"
    }
  },
  "components": [
    {"type": "library", "name": "swift-service-lifecycle", "version": "2.x"},
    {"type": "library", "name": "swift-argument-parser", "version": "1.x"},
    {"type": "library", "name": "GRDB.swift", "version": "7.x"}
  ]
}
EOF
  echo "Stub: $OUT"
fi
