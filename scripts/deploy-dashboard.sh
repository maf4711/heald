#!/usr/bin/env bash
# Always deploy heald dashboard to PRODUCTION (never preview).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCOPE="${VERCEL_SCOPE:-marco-3586s-projects}"

echo "==> heald dashboard → PRODUCTION ($SCOPE/heald)"
echo "    rootDirectory=dashboard · target=production"
exec vercel --prod --yes --scope "$SCOPE"
