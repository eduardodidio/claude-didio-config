#!/usr/bin/env bash
# F25 unit test — static validation of all settings.json files + hook resolution
# Run: bash bin/tests/F25-unit.sh
# Covers: AC1 (no {{ in any target), AC2 (pre-tool hook resolves), JSON validity,
#         shell fallback expansion, framework hook pattern in template.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE_SETTINGS="$REPO_ROOT/templates/.claude/settings.json"
UPSTREAM_SETTINGS="$REPO_ROOT/.claude/settings.json"
DOWNSTREAM_ROOTS=(
  /Users/eduardodidio/blind-warrior
  /Users/eduardodidio/escudo-do-mestre-v1
  /Users/eduardodidio/access-play-create
  /Users/eduardodidio/mellon-magic-maker
  /Users/eduardodidio/mellon-bot
  /Users/eduardodidio/didio-second-brain-claude
  /Users/eduardodidio/didio-second-brain-clean-starter
)

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# 1. JSON validity — template and upstream
# ---------------------------------------------------------------------------
for label_file in "template:$TEMPLATE_SETTINGS" "upstream:$UPSTREAM_SETTINGS"; do
  label="${label_file%%:*}"
  f="${label_file#*:}"
  if python3 -m json.tool "$f" >/dev/null 2>&1; then
    pass "JSON valid: $label"
  else
    fail "JSON invalid: $label ($f)"
  fi
done

# ---------------------------------------------------------------------------
# 2. No {{ placeholders in template and upstream
# ---------------------------------------------------------------------------
for label_file in "template:$TEMPLATE_SETTINGS" "upstream:$UPSTREAM_SETTINGS"; do
  label="${label_file%%:*}"
  f="${label_file#*:}"
  count=$(grep -c '{{' "$f" 2>/dev/null; true)
  if [[ "$count" -eq 0 ]]; then
    pass "no {{ in $label settings.json"
  else
    fail "$label settings.json has $count line(s) with {{ placeholder"
  fi
done

# ---------------------------------------------------------------------------
# 3. Template uses ${DIDIO_HOME:-...} convention for framework hooks
# ---------------------------------------------------------------------------
if grep -qF '${DIDIO_HOME:-' "$TEMPLATE_SETTINGS"; then
  pass "template framework hooks use \${DIDIO_HOME:-...} convention"
else
  fail "template does not use \${DIDIO_HOME:-...} for framework hooks"
fi

if grep -qF '{{' "$TEMPLATE_SETTINGS"; then
  fail "template still contains {{ placeholder(s)"
else
  pass "template: no second-brain placeholder hooks"
fi

# ---------------------------------------------------------------------------
# 4. No {{ in all 7 downstream settings.json (AC1)
# ---------------------------------------------------------------------------
for root in "${DOWNSTREAM_ROOTS[@]}"; do
  f="$root/.claude/settings.json"
  proj="$(basename "$root")"
  if [[ ! -f "$f" ]]; then
    fail "downstream $proj: settings.json missing"
    continue
  fi
  count=$(grep -c '{{' "$f" 2>/dev/null; true)
  if [[ "$count" -eq 0 ]]; then
    pass "no {{ in downstream $proj"
  else
    fail "downstream $proj: $count line(s) with {{ placeholder"
  fi
done

# ---------------------------------------------------------------------------
# 5. JSON validity — all 7 downstream
# ---------------------------------------------------------------------------
for root in "${DOWNSTREAM_ROOTS[@]}"; do
  f="$root/.claude/settings.json"
  proj="$(basename "$root")"
  if [[ ! -f "$f" ]]; then
    # already reported above
    continue
  fi
  if python3 -m json.tool "$f" >/dev/null 2>&1; then
    pass "JSON valid: $proj"
  else
    fail "JSON invalid: $proj"
  fi
done

# ---------------------------------------------------------------------------
# 6. Generic downstream: no DIDIO_SECOND_BRAIN_HOME hooks (AC3)
# ---------------------------------------------------------------------------
GENERIC_DOWNSTREAMS=(
  /Users/eduardodidio/blind-warrior
  /Users/eduardodidio/escudo-do-mestre-v1
  /Users/eduardodidio/access-play-create
  /Users/eduardodidio/mellon-magic-maker
  /Users/eduardodidio/mellon-bot
  /Users/eduardodidio/didio-second-brain-clean-starter
)
for root in "${GENERIC_DOWNSTREAMS[@]}"; do
  f="$root/.claude/settings.json"
  proj="$(basename "$root")"
  if [[ ! -f "$f" ]]; then
    continue
  fi
  if grep -q 'DIDIO_SECOND_BRAIN_HOME' "$f" 2>/dev/null; then
    fail "$proj: contains DIDIO_SECOND_BRAIN_HOME hook (should be removed)"
  else
    pass "$proj: no DIDIO_SECOND_BRAIN_HOME hook"
  fi
done

# ---------------------------------------------------------------------------
# 7. Shell fallback expansion (DIDIO_HOME unset → $HOME/.claude-didio-config)
# ---------------------------------------------------------------------------
FALLBACK=$(DIDIO_HOME= bash -c 'echo ${DIDIO_HOME:-$HOME/.claude-didio-config}' 2>/dev/null)
EXPECTED="$HOME/.claude-didio-config"
if [[ "$FALLBACK" == "$EXPECTED" ]]; then
  pass "shell fallback: DIDIO_HOME unset → $EXPECTED"
else
  fail "shell fallback mismatch: got '$FALLBACK', expected '$EXPECTED'"
fi

# ---------------------------------------------------------------------------
# 8. didio-pre-tool.sh executes without ENOENT (AC2)
# ---------------------------------------------------------------------------
DIDIO_HOME="$REPO_ROOT" bash "$REPO_ROOT/bin/hooks/didio-pre-tool.sh" 2>/dev/null
EXIT_CODE=$?
if [[ "$EXIT_CODE" -ne 127 ]]; then
  pass "didio-pre-tool.sh executes without 'No such file' (exit $EXIT_CODE)"
else
  fail "didio-pre-tool.sh: command not found (exit 127)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
