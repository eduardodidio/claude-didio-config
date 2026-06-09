#!/usr/bin/env bash
# tests/F24-skill-materialization.sh — validates the
# install-claude-didio-framework skill's second-brain wiring against
# templates/.claude/settings.json under the F25 model.
#
# F25 retired the {{DIDIO_HOME}}/{{DIDIO_SECOND_BRAIN_HOME}} mustache
# placeholders: hook commands now use runtime ${DIDIO_HOME:-…} expansion and
# the generic template ships with NO second-brain hooks. So:
#   - default ("no")  → settings.json is copied verbatim (no second-brain).
#   - opt-in ("yes")  → the skill APPENDS env-style second-brain hooks.
# We don't run the prompt-driven skill; we replicate the exact append step
# (SKILL.md step 4.5) and assert the result.
#
# Hermetic: mktemp sandbox; no real $HOME mutation.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$THIS_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/templates/.claude/settings.json"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# ---------------------------------------------------------------------------
# Pre-flight: the source template must be F25-shaped.
# ---------------------------------------------------------------------------
if [ "$(grep -c '/Users/eduardodidio/' "$TEMPLATE")" -eq 0 ]; then
  pass "template has no hardcoded author paths"
else
  fail "template still contains /Users/eduardodidio/ literals"
fi

if grep -qE '\{\{DIDIO_(HOME|SECOND_BRAIN_HOME)\}\}' "$TEMPLATE"; then
  fail "template still has retired {{DIDIO_*}} mustache placeholders (F25 removed them)"
else
  pass "template has no mustache placeholders (F25 model)"
fi

grep -q 'bash ${DIDIO_HOME:-' "$TEMPLATE" \
  && pass "template hooks use runtime \${DIDIO_HOME:-…} expansion" \
  || fail "template hooks missing \${DIDIO_HOME:-…} expansion"

if grep -q 'DIDIO_SECOND_BRAIN_HOME' "$TEMPLATE"; then
  fail "generic template should NOT ship second-brain hooks (F25)"
else
  pass "generic template ships no second-brain hooks"
fi

# Exact append the skill performs (SKILL.md step 4.5, yes-branch, point 3).
append_sb_hooks() {
  python3 - "$1" <<'PY'
import json, sys
p = sys.argv[1]
CMD = ('bash ${DIDIO_SECOND_BRAIN_HOME:-$HOME/didio-second-brain-claude}'
       '/patterns/hooks/stop-session-summary/hook.sh')
with open(p) as f: s = json.load(f)
hooks = s.setdefault('hooks', {})
for key in ('Stop', 'SubagentStop'):
    entries = hooks.setdefault(key, [])
    if any('DIDIO_SECOND_BRAIN_HOME' in h.get('command', '')
           for e in entries for h in e.get('hooks', [])):
        continue
    entries.append({'matcher': '*',
                    'hooks': [{'type': 'command', 'command': CMD}]})
with open(p, 'w') as f:
    json.dump(s, f, indent=2); f.write('\n')
PY
}

sb_hook_count() {
  python3 -c "import json;s=json.load(open('$1'));print(sum(1 for k in s.get('hooks',{}) for e in s['hooks'][k] for h in e.get('hooks',[]) if 'DIDIO_SECOND_BRAIN_HOME' in h.get('command','')))"
}

# ---------------------------------------------------------------------------
# Scenario A — "yes" branch: skill appends env-style second-brain hooks.
# ---------------------------------------------------------------------------
SCENARIO_A="$SANDBOX/yes/.claude"
mkdir -p "$SCENARIO_A"
cp "$TEMPLATE" "$SCENARIO_A/settings.json"
append_sb_hooks "$SCENARIO_A/settings.json"

[ "$(grep -c '/Users/eduardodidio/' "$SCENARIO_A/settings.json" || true)" -eq 0 ] \
  && pass "yes-branch: no /Users/eduardodidio/ literal" \
  || fail "yes-branch: /Users/eduardodidio/ present"

grep -q 'DIDIO_SECOND_BRAIN_HOME:-' "$SCENARIO_A/settings.json" \
  && pass "yes-branch: env-style second-brain hook appended" \
  || fail "yes-branch: env-style second-brain hook missing"

if grep -qE '\{\{' "$SCENARIO_A/settings.json"; then
  fail "yes-branch: leftover mustache placeholder"
else
  pass "yes-branch: no mustache placeholders"
fi

grep -q 'bash ${DIDIO_HOME:-.*}/bin/hooks/didio-pre-tool.sh' "$SCENARIO_A/settings.json" \
  && pass "yes-branch: didio framework hooks intact" \
  || fail "yes-branch: didio framework hooks altered"

python3 -c "import json; json.load(open('$SCENARIO_A/settings.json'))" 2>/dev/null \
  && pass "yes-branch: JSON valid" \
  || fail "yes-branch: JSON invalid after append"

# Idempotency: a second append must not add a duplicate.
before="$(sb_hook_count "$SCENARIO_A/settings.json")"
append_sb_hooks "$SCENARIO_A/settings.json"
after="$(sb_hook_count "$SCENARIO_A/settings.json")"
[ "$before" = "$after" ] \
  && pass "yes-branch: append is idempotent ($before second-brain hooks)" \
  || fail "yes-branch: append not idempotent (before=$before after=$after)"

# ---------------------------------------------------------------------------
# Scenario B — "no" branch: settings.json copied verbatim.
# ---------------------------------------------------------------------------
SCENARIO_B="$SANDBOX/no/.claude"
mkdir -p "$SCENARIO_B"
cp "$TEMPLATE" "$SCENARIO_B/settings.json"

[ "$(grep -c '/Users/eduardodidio/' "$SCENARIO_B/settings.json" || true)" -eq 0 ] \
  && pass "no-branch: no /Users/eduardodidio/ literal" \
  || fail "no-branch: /Users/eduardodidio/ present"

if grep -q 'DIDIO_SECOND_BRAIN_HOME' "$SCENARIO_B/settings.json"; then
  fail "no-branch: unexpected second-brain hook present"
else
  pass "no-branch: no second-brain hooks (verbatim)"
fi

grep -q 'bash ${DIDIO_HOME:-.*}/bin/hooks/didio-post-tool.sh' "$SCENARIO_B/settings.json" \
  && pass "no-branch: didio framework hooks present" \
  || fail "no-branch: didio framework hooks missing"

python3 -c "import json; json.load(open('$SCENARIO_B/settings.json'))" 2>/dev/null \
  && pass "no-branch: JSON valid" \
  || fail "no-branch: JSON invalid"

if [ "$FAIL" -ne 0 ]; then
  echo "----"
  echo "F24-skill-materialization.sh: FAILED"
  exit 1
fi
echo "----"
echo "F24-skill-materialization.sh: ALL PASS"
