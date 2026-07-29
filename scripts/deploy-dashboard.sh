#!/usr/bin/env bash
# Always deploy heald dashboard to PRODUCTION (never preview).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/dashboard"

SCOPE="${VERCEL_SCOPE:-marco-3586s-projects}"
PROJECT="${VERCEL_PROJECT:-heald}"

echo "==> heald dashboard → PRODUCTION ($SCOPE/$PROJECT)"
exec vercel --prod --yes --scope "$SCOPE"
