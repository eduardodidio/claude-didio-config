#!/usr/bin/env bash
# F10-readiness-smoke.sh — smoke runner for the readiness agent fixtures.
#
# Runs the `readiness` agent against 5 synthetic fixtures and compares
# each verdict to the expected value. Exit 0 if all match; exit 1 otherwise.
#
# Cost: ~3 min total (5 fixtures × ~30s per claude call).
# Usage: bash tests/F10-readiness-smoke.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$(cd "$SCRIPT_DIR/.." && pwd)"

trap 'rm -rf "$PROJECT/tasks/features/F99-"*' EXIT

declare -A EXPECTED=(
  [ready]=READY
  [missing-ac]=BLOCKED
  [file-collision]=BLOCKED
  [no-testing]=BLOCKED
  [bad-wave0]=BLOCKED
)

PASS=0
FAIL=0

echo "=== F10 readiness smoke tests ==="
echo ""

for FIX in "${!EXPECTED[@]}"; do
  echo "--- Fixture: $FIX ---"

  SRC="$PROJECT/tests/F10-fixtures/$FIX"
  DST="$PROJECT/tasks/features/F99-${FIX}"
  cp -r "$SRC" "$DST"

  "$PROJECT/bin/didio" spawn-agent readiness F99 "$DST/F99-README.md" \
    "Audit fixture $FIX. Write the report at $DST/readiness-report.md."

  REPORT="$DST/readiness-report.md"
  if [[ ! -f "$REPORT" ]]; then
    echo "  ❌ $FIX: report not created"
    (( FAIL++ )) || true
    rm -rf "$DST"
    continue
  fi

  ACTUAL=$(grep -oE '^\*\*Verdict:\*\* (READY|BLOCKED)' "$REPORT" | tail -1 | awk '{print $2}')

  if [[ "$ACTUAL" == "${EXPECTED[$FIX]}" ]]; then
    echo "  ✅ $FIX (got $ACTUAL)"
    (( PASS++ )) || true
  else
    echo "  ❌ $FIX (expected ${EXPECTED[$FIX]}, got '$ACTUAL')"
    (( FAIL++ )) || true
  fi

  rm -rf "$DST"
done

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"

if (( FAIL > 0 )); then
  echo "FIXTURES FAILED"
  exit 1
fi
echo "ALL FIXTURES PASSED"
