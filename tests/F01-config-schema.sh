#!/usr/bin/env bash
# tests/F01-config-schema.sh — Smoke test for the providers registry +
# per-role provider key added to didio.config.json / templates/didio.config.json.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc"
    FAIL=$((FAIL+1))
  fi
}

CFG="didio.config.json"
TEMPLATE="templates/didio.config.json"

# --- Happy path: valid JSON + providers registry ---
check "$CFG is valid JSON" python3 -c "import json; json.load(open('$CFG'))"
check "$TEMPLATE is valid JSON" python3 -c "import json; json.load(open('$TEMPLATE'))"

check "$CFG providers.claude.bin == claude" python3 -c "
import json
cfg = json.load(open('$CFG'))
assert cfg['providers']['claude']['bin'] == 'claude'
"
check "$CFG providers.codex.bin == codex" python3 -c "
import json
cfg = json.load(open('$CFG'))
assert cfg['providers']['codex']['bin'] == 'codex'
"
check "$TEMPLATE providers.claude.bin == claude" python3 -c "
import json
cfg = json.load(open('$TEMPLATE'))
assert cfg['providers']['claude']['bin'] == 'claude'
"
check "$TEMPLATE providers.codex.bin == codex" python3 -c "
import json
cfg = json.load(open('$TEMPLATE'))
assert cfg['providers']['codex']['bin'] == 'codex'
"

# --- Edge case: roles with no 'provider' key still load; existing model
#     values were not altered by the schema change ---
check "$CFG roles load without 'provider' key" python3 -c "
import json
cfg = json.load(open('$CFG'))
for role, entry in cfg['models'].items():
    assert 'model' in entry, role
"

check "no existing models.<role>.model value changed (vs git HEAD)" bash -c "
git diff HEAD -- '$CFG' | grep -E '^[+-]' | grep -v '^[+-][+-][+-]' | grep -E '\"(model|fallback|effort)\"' && exit 1 || exit 0
"

# --- Error scenario: malformed JSON is caught ---
check "malformed JSON is rejected" bash -c "
python3 -c \"import json; json.loads('{\\\"a\\\": 1,}')\" 2>/dev/null && exit 1 || exit 0
"

# --- Boundary: template has zero roles defaulted to codex ---
check "template has no roles defaulted to codex" bash -c "
! grep -q '\"provider\": \"codex\"' '$TEMPLATE'
"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
