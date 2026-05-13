#!/usr/bin/env bash
# F24-readme.sh — drift guard for README.md (rate-limit recovery section,
# env vars table, --help snippet, ADR-0014 link).
# Hermetic: mktemp sandbox, no real $HOME mutation, no network, no API.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_HOME="$(cd "$THIS_DIR/.." && pwd)"
export DIDIO_HOME

README="$DIDIO_HOME/README.md"
SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# 1. Headings.
[ "$(grep -c '^## Rate-limit recovery' "$README")" -eq 1 ] \
  && pass "Rate-limit recovery heading" \
  || fail "missing or duplicated '## Rate-limit recovery'"

[ "$(grep -c '^### Troubleshooting: agent spawn falhou com exit 1' "$README")" -eq 1 ] \
  && pass "Troubleshooting subsection" \
  || fail "missing or duplicated '### Troubleshooting: agent spawn falhou com exit 1'"

# 2. Env-vars table (5 rows).
for v in DIDIO_HOME DIDIO_CI DIDIO_MAX_RETRIES DIDIO_ON_RATE_LIMIT DIDIO_PLAN_ONLY; do
  if grep -qE "^\| \`$v\`" "$README"; then
    pass "env var row: $v"
  else
    fail "env var row missing: $v"
  fi
done

# 3. ADR-0014 link.
grep -q '0014-rate-limit-auto-resume' "$README" \
  && pass "ADR-0014 link present" \
  || fail "ADR-0014 link missing"

# 4. Snippet markers.
[ "$(grep -c '<!-- f24:help-snippet:start -->' "$README")" -eq 1 ] \
  && pass "snippet start marker" \
  || fail "missing/duplicated snippet start marker"
[ "$(grep -c '<!-- f24:help-snippet:end -->' "$README")" -eq 1 ] \
  && pass "snippet end marker" \
  || fail "missing/duplicated snippet end marker"

# 5. Snippet content == live --help.
awk '
  /<!-- f24:help-snippet:start -->/ { capture=1; next }
  /<!-- f24:help-snippet:end -->/   { capture=0 }
  capture
' "$README" > "$SANDBOX/snippet.raw"

# Strip leading ```text and trailing ``` fence lines.
sed -e '1{/^```text$/d;}' -e '${/^```$/d;}' "$SANDBOX/snippet.raw" > "$SANDBOX/snippet.txt"

if [ ! -s "$SANDBOX/snippet.txt" ]; then
  fail "snippet block is empty between markers"
else
  "$DIDIO_HOME/bin/didio" spawn-agent --help > "$SANDBOX/live.txt" 2>&1 \
    || { fail "didio spawn-agent --help exited non-zero"; exit 1; }

  # Trim trailing whitespace on both sides for comparison.
  sed -e 's/[[:space:]]*$//' "$SANDBOX/snippet.txt" > "$SANDBOX/snippet.norm"
  sed -e 's/[[:space:]]*$//' "$SANDBOX/live.txt"    > "$SANDBOX/live.norm"

  if diff -u "$SANDBOX/snippet.norm" "$SANDBOX/live.norm" > "$SANDBOX/diff.out"; then
    pass "--help snippet in README is in sync with live binary"
  else
    fail "--help snippet drift detected:"
    cat "$SANDBOX/diff.out"
  fi
fi

if [ "$FAIL" -ne 0 ]; then
  echo "----"
  echo "F24-readme.sh: FAILED"
  exit 1
fi
echo "----"
echo "F24-readme.sh: ALL PASS"
