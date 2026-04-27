#!/usr/bin/env bash
# F11-T07 — Dry-run sync sanity: verifies F11 propagates elicit-prd files downstream
set -euo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; RESET='\033[0m'
PASS=0; FAIL=0

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Fixture setup with safety guard
# ---------------------------------------------------------------------------
TMPDIR_REAL="$(cd "${TMPDIR:-/tmp}" && pwd)"
FIXTURE="$(mktemp -d -t F11-sync-fixture-XXXXXX)"
# Trap set immediately after mktemp so cleanup fires even if the guard below rejects.
# The trap re-validates the prefix before rm -rf as a defense-in-depth measure.
trap '
  case "$FIXTURE" in
    /tmp/*|"$TMPDIR_REAL"/*)
      rm -rf "$FIXTURE" ;;
    *)
      echo "WARN: skipping rm -rf on suspect path: $FIXTURE" >&2 ;;
  esac
' EXIT
case "$FIXTURE" in
  /tmp/*|"$TMPDIR_REAL"/*) ;;
  *) echo "ERROR: fixture path suspect: $FIXTURE"; exit 2 ;;
esac

git -C "$FIXTURE" init -q
git -C "$FIXTURE" -c user.email='test@example.com' -c user.name='F11-Test' \
  commit --allow-empty -q -m "init"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
assert_grep() {
  local pattern="$1"
  local label="$2"
  local output="$3"
  if echo "$output" | grep -qF "$pattern"; then
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${RESET}: $label (pattern not found: '$pattern')"
    FAIL=$((FAIL + 1))
  fi
}

assert_no_match() {
  local pattern="$1"
  local label="$2"
  local output="$3"
  if echo "$output" | grep -qE "$pattern"; then
    echo -e "${RED}FAIL${RESET}: $label (unexpected pattern found: '$pattern')"
    FAIL=$((FAIL + 1))
  else
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  fi
}

assert_cooccur() {
  local path="$1"
  local token="$2"
  local label="$3"
  local output="$4"
  if echo "$output" | grep -F "$path" | grep -qF "$token"; then
    echo -e "${GREEN}PASS${RESET}: $label"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}FAIL${RESET}: $label (path '$path' not seen with token '$token')"
    FAIL=$((FAIL + 1))
  fi
}

run_sync() {
  local fixture="$1"
  local rc=0
  DIDIO_HOME="$ROOT" "$ROOT/bin/didio-sync-project.sh" \
    --dry-run "$fixture" 2>&1 \
    | sed 's/\x1b\[[0-9;]*m//g' \
    || rc=$?
  return $rc
}

# ---------------------------------------------------------------------------
# Run 1
# ---------------------------------------------------------------------------
echo "=== Run 1 ==="
OUTPUT="$(run_sync "$FIXTURE")"
RC=$?

# Exit code must be 0
if [[ $RC -eq 0 ]]; then
  echo -e "${GREEN}PASS${RESET}: dry-run exited 0"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${RESET}: dry-run exited $RC (expected 0)"
  FAIL=$((FAIL + 1))
fi

# AC5 — elicit-questions.md propagated
assert_cooccur "docs/prd/elicit-questions.md" "[ADDED]" \
  "AC5 — docs/prd/elicit-questions.md ADDED" "$OUTPUT"

# AC5 — elicit-prd slash command propagated (via Section 4 .claude/commands sync)
assert_cooccur ".claude/commands/elicit-prd.md" "[ADDED]" \
  "AC5 — .claude/commands/elicit-prd.md ADDED" "$OUTPUT"

# Baseline non-regression: template.md still propagated
assert_cooccur "docs/prd/template.md" "[ADDED]" \
  "baseline — docs/prd/template.md ADDED" "$OUTPUT"

# No unexpected errors
assert_no_match 'ERROR|Aborting|Traceback' \
  "no errors/aborts/tracebacks in dry-run output" "$OUTPUT"

# ---------------------------------------------------------------------------
# Run 2 — idempotency (fixture unchanged because --dry-run wrote nothing)
# ---------------------------------------------------------------------------
echo
echo "=== Run 2 (idempotency) ==="
OUTPUT2="$(run_sync "$FIXTURE")"
RC2=$?

if [[ $RC2 -eq 0 ]]; then
  echo -e "${GREEN}PASS${RESET}: second dry-run exited 0"
  PASS=$((PASS + 1))
else
  echo -e "${RED}FAIL${RESET}: second dry-run exited $RC2 (expected 0)"
  FAIL=$((FAIL + 1))
fi

# Second run should still show same ADDED lines (fixture still empty)
assert_cooccur "docs/prd/elicit-questions.md" "[ADDED]" \
  "idempotent — elicit-questions.md still ADDED on 2nd run" "$OUTPUT2"

assert_cooccur ".claude/commands/elicit-prd.md" "[ADDED]" \
  "idempotent — elicit-prd.md still ADDED on 2nd run" "$OUTPUT2"

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] || exit 1
