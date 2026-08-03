#!/usr/bin/env bash
# Build a ZIP for security review (P1.1).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
OUT_DIR="$ROOT/dist"
STAMP=$(date +%Y%m%d)
ZIP="$OUT_DIR/heald-reviewer-pack-${STAMP}.zip"
STAGE=$(mktemp -d -t heald-review)

mkdir -p "$OUT_DIR" "$STAGE/docs" "$STAGE/samples"

# Docs
for f in ROADMAP.md THREAT-MODEL.md BANK-ONEPAGER.md ELON-CUT-BANK.md ENTERPRISE.md PILOT.md; do
  [[ -f "docs/$f" ]] && cp "docs/$f" "$STAGE/docs/"
done

# Live samples if heald available
if command -v heald >/dev/null 2>&1; then
  heald --version > "$STAGE/samples/version.txt" 2>/dev/null || true
  heald policy --preset bank >/dev/null 2>&1 || true
  heald policy > "$STAGE/samples/policy.bank.json" 2>/dev/null || true
  heald enroll --show > "$STAGE/samples/device-show.txt" 2>/dev/null || true
  heald compliance > "$STAGE/samples/compliance.json" 2>/dev/null || true
  heald doctor > "$STAGE/samples/doctor.txt" 2>/dev/null || true
fi

# Already on disk
[[ -f "$HOME/.heald/compliance/compliance-latest.json" ]] && \
  cp "$HOME/.heald/compliance/compliance-latest.json" "$STAGE/samples/" || true

cat > "$STAGE/README.txt" <<EOF
heald Security Reviewer Pack
Generated: $(date -u +%Y-%m-%dT%H:%MZ)

Read order:
  1. docs/BANK-ONEPAGER.md
  2. docs/THREAT-MODEL.md
  3. docs/ROADMAP.md
  4. samples/compliance.json
  5. samples/doctor.txt

Bank mode: consent=log, cloud off, no process kill.
Kill-switch: heald policy --consent log --cloud-off
EOF

rm -f "$ZIP"
(
  cd "$STAGE"
  zip -r "$ZIP" . -x "*.DS_Store" >/dev/null
)
rm -rf "$STAGE"
echo "Reviewer pack: $ZIP"
ls -lh "$ZIP"
