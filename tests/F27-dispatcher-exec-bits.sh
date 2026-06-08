#!/usr/bin/env bash
# F27 — Guard: every script the `didio` dispatcher exec's must be executable.
#
# Regression guard for the bug found 2026-06-08: didio-t800.sh,
# didio-t1000.sh and didio-decisions.sh shipped without the exec bit, so
# `didio t800` / `didio t1000` / `didio decisions` (and the t800->t1000
# auto-governance handoff) failed with "Permission denied" (exit 126).
#
# The list is DERIVED from bin/didio so new subcommands are covered
# automatically. Pure libraries (sourced, never exec'd) are intentionally
# out of scope — they don't need +x.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISPATCHER="$REPO_ROOT/bin/didio"

pass=0
fail=0

check_exec() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo "  FAIL [$f] referenced by dispatcher but missing"
    fail=$((fail+1))
  elif [[ -x "$f" ]]; then
    echo "  ok   [$(basename "$f")] is executable"
    pass=$((pass+1))
  else
    echo "  FAIL [$(basename "$f")] is NOT executable (exec would exit 126)"
    fail=$((fail+1))
  fi
}

echo "[F27] dispatcher entrypoint executable"
check_exec "$DISPATCHER"

echo "[F27] scripts exec'd by the dispatcher"
# Extract `exec "$DIDIO_HOME/bin/<name>.sh"` targets from the dispatcher.
# bash-3.2 compatible (no mapfile): iterate via while-read.
count=0
while IFS= read -r rel; do
  [[ -n "$rel" ]] || continue
  count=$((count+1))
  check_exec "$REPO_ROOT/$rel"
done < <(
  grep -oE 'exec "\$DIDIO_HOME/bin/[a-z0-9-]+\.sh"' "$DISPATCHER" \
    | grep -oE 'bin/[a-z0-9-]+\.sh' | sort -u
)

if [[ $count -eq 0 ]]; then
  echo "  FAIL could not parse any dispatched scripts from $DISPATCHER"
  fail=$((fail+1))
fi

echo
echo "[F27] pass=$pass fail=$fail"
exit $(( fail > 0 ? 1 : 0 ))
