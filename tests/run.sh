#!/usr/bin/env bash
# tests/run.sh — canonical framework test runner.
#
# Runs the pure unit/smoke suite to green. Tests that need a real `claude`
# session, are timing/signal-sensitive e2e, depend on an external tool, or are
# parametrized helpers are SKIPPED by default with a printed reason — running
# `bash tests/*.sh` blindly mis-reports these as failures.
#
#   bash tests/run.sh                 # pure suite (skips e2e/infra/param)
#   DIDIO_RUN_E2E=1 bash tests/run.sh # also run e2e (needs claude auth)
#
# Exit non-zero iff a test that actually ran failed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# E2E: need real `claude` auth, or are process/signal-timing sensitive.
#   F06-integration-test  — second-brain migrate-learnings step blocks offline
#   F07-pause-resume-e2e  — SIGTERM/PID-timing sensitive (flaky)
#   F10-readiness-smoke   — 5 live `claude` calls (~3 min)
#   F13-tea-e2e           — live TEA spawn (honors its own DIDIO_E2E=skip)
E2E=(F06-integration-test F07-pause-resume-e2e F10-readiness-smoke F13-tea-e2e)
# Parametrized helpers: require positional args; driven by a sibling test.
PARAM=(F13-tea-smoke)

PASS=0; FAIL=0; SKIP=0; FAILED=()
TMP_OUT="$(mktemp)"; trap 'rm -f "$TMP_OUT"' EXIT

in_list() { local x="$1"; shift; local e; for e in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }

# Portable per-test timeout (no coreutils `timeout` on stock macOS).
run_to() {
  local secs="$1"; shift
  "$@" >"$TMP_OUT" 2>&1 & local p=$!
  ( sleep "$secs"; kill -9 "$p" 2>/dev/null ) & local w=$!
  if wait "$p" 2>/dev/null; then kill "$w" 2>/dev/null; return 0; fi
  local rc=$?; kill "$w" 2>/dev/null; return "$rc"
}

echo "=== didio framework test runner ==="
echo ""

shopt -s nullglob
for f in "$ROOT"/tests/F*-*.sh; do
  b="$(basename "$f" .sh)"

  if in_list "$b" "${PARAM[@]}"; then
    echo "SKIP  $b — parametrized helper (needs args)"; SKIP=$((SKIP+1)); continue
  fi
  if in_list "$b" "${E2E[@]}" && [[ "${DIDIO_RUN_E2E:-0}" != "1" ]]; then
    echo "SKIP  $b — e2e (DIDIO_RUN_E2E=1 to run; needs claude auth)"; SKIP=$((SKIP+1)); continue
  fi
  if [[ "$b" == "F07-budget-smoke" ]] && ! command -v ccusage >/dev/null 2>&1; then
    echo "SKIP  $b — needs ccusage (not installed)"; SKIP=$((SKIP+1)); continue
  fi

  if run_to 180 bash "$f"; then
    echo "PASS  $b"; PASS=$((PASS+1))
  else
    rc=$?
    echo "FAIL  $b (rc=$rc)"; sed 's/^/      /' "$TMP_OUT" | tail -12
    FAIL=$((FAIL+1)); FAILED+=("$b")
  fi
done
shopt -u nullglob

echo ""
echo "--- $PASS passed, $FAIL failed, $SKIP skipped ---"
if [[ $FAIL -gt 0 ]]; then
  echo ""; echo "Failed:"; for x in "${FAILED[@]}"; do echo "  - $x"; done
  exit 1
fi
