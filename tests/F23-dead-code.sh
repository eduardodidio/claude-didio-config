#!/usr/bin/env bash
# F23-T07 — assert PENDING_AFTER dead-code is gone from run-wave.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$REPO_ROOT/bin/didio-run-wave.sh"

if [[ ! -f "$TARGET" ]]; then
  echo "FAIL: missing $TARGET"
  exit 1
fi

pass=0
fail=0

echo "[F23-T07] PENDING_AFTER absent from $TARGET"
if grep -q 'PENDING_AFTER' "$TARGET"; then
  echo "  FAIL: PENDING_AFTER still present:"
  grep -n 'PENDING_AFTER' "$TARGET" | head -5
  fail=$((fail+1))
else
  echo "  ok"
  pass=$((pass+1))
fi

echo "[F23-T07] removal documented inline (F23 or ADR-0014 reference)"
if grep -qE 'F23|ADR-0014' "$TARGET"; then
  echo "  ok"
  pass=$((pass+1))
else
  echo "  FAIL: no F23 / ADR-0014 reference in run-wave.sh"
  echo "         (T02 should have left a comment explaining the removal)"
  fail=$((fail+1))
fi

echo "[F23-T07] bash -n parses"
if bash -n "$TARGET"; then
  echo "  ok"
  pass=$((pass+1))
else
  echo "  FAIL: bash -n failed on $TARGET"
  fail=$((fail+1))
fi

echo
echo "[F23-T07] pass=$pass fail=$fail"
exit $(( fail > 0 ? 1 : 0 ))
