#!/usr/bin/env bash
# P1.4 automated smoke: doctor → compliance → kill-switch → enroll show
set -euo pipefail
HEALD="${HEALD_BIN:-heald}"
if ! command -v "$HEALD" >/dev/null 2>&1 && [[ -x "${HOME}/Library/heald/heald" ]]; then
  HEALD="${HOME}/Library/heald/heald"
fi
if [[ ! -x "$(command -v "$HEALD" 2>/dev/null || echo /nonexistent)" ]] && [[ -x "$HEALD" ]]; then
  :
elif [[ -x "$HEALD" ]]; then
  :
elif command -v heald >/dev/null; then
  HEALD=$(command -v heald)
else
  echo "FAIL: heald not found" >&2
  exit 1
fi

pass=0
fail=0
check() {
  local name="$1"
  shift
  if "$@" >/tmp/heald-smoke.out 2>/tmp/heald-smoke.err; then
    echo "PASS  $name"
    pass=$((pass + 1))
  else
    echo "FAIL  $name"
    cat /tmp/heald-smoke.err | head -5
    fail=$((fail + 1))
  fi
}

echo "heald smoke-test ($HEALD)"
echo "version: $($HEALD --version 2>/dev/null || true)"

check "version" "$HEALD" --version
check "policy-bank" "$HEALD" policy --preset bank
check "consent-log" bash -c "grep -q '\"consent\" : \"log\"' ~/.heald/policy.json || grep -q '\"consent\":\"log\"' ~/.heald/policy.json"
check "cloud-off" bash -c "grep -q '\"cloudEnabled\" : false' ~/.heald/policy.json || grep -q '\"cloudEnabled\":false' ~/.heald/policy.json"
check "enroll-show" "$HEALD" enroll --show
check "doctor" "$HEALD" doctor
check "compliance-schema" bash -c "$HEALD compliance >/tmp/heald-comp-smoke.json 2>/dev/null; grep -qE 'heald\\.compliance' /tmp/heald-comp-smoke.json"
check "kill-switch-cloud" "$HEALD" policy --cloud-off
check "kill-switch-consent" "$HEALD" policy --consent log

echo ""
echo "passed=$pass failed=$fail"
[[ "$fail" -eq 0 ]]
