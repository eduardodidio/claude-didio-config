#!/usr/bin/env bash
# tests/F24-skill-materialization.sh — simulates the
# install-claude-didio-framework skill's substitution step against
# templates/.claude/settings.json, then asserts AC3/AC4 from F24-README.
#
# We don't run the full skill (it's prompt-driven). We replicate exactly the
# two substitution operations the skill performs:
#   yes-branch: sed s|{{DIDIO_HOME}}|$DIDIO_HOME_RESOLVED|g
#               sed s|{{DIDIO_SECOND_BRAIN_HOME}}|$SB_HOME_RESOLVED|g
#   no-branch:  same DIDIO_HOME sub + python3 strip of {{DIDIO_SECOND_BRAIN_HOME}} hook entries
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
# Pre-flight: the source template itself MUST NOT contain author paths.
# ---------------------------------------------------------------------------
if [ "$(grep -c '/Users/eduardodidio/' "$TEMPLATE")" -eq 0 ]; then
  pass "template has no hardcoded author paths"
else
  fail "templates/.claude/settings.json still contains /Users/eduardodidio/ literals"
fi

# Both placeholders must be present in the template.
grep -q '{{DIDIO_HOME}}' "$TEMPLATE" \
  && pass "template has {{DIDIO_HOME}} placeholder" \
  || fail "template missing {{DIDIO_HOME}} placeholder"
grep -q '{{DIDIO_SECOND_BRAIN_HOME}}' "$TEMPLATE" \
  && pass "template has {{DIDIO_SECOND_BRAIN_HOME}} placeholder" \
  || fail "template missing {{DIDIO_SECOND_BRAIN_HOME}} placeholder"

# ---------------------------------------------------------------------------
# Scenario A — yes-branch (user opts in to second-brain).
#   Simulates: skill sets DIDIO_HOME_RESOLVED + SB_HOME_RESOLVED and runs both
#   sed substitutions on the materialized copy.
# ---------------------------------------------------------------------------
SCENARIO_A="$SANDBOX/yes/.claude"
mkdir -p "$SCENARIO_A"
cp "$TEMPLATE" "$SCENARIO_A/settings.json"

FAKE_DIDIO_HOME="/opt/fake/didio-framework"
FAKE_SB_HOME="/opt/fake/didio-second-brain-claude"

sed -i.bak "s|{{DIDIO_HOME}}|$FAKE_DIDIO_HOME|g" "$SCENARIO_A/settings.json"
sed -i.bak "s|{{DIDIO_SECOND_BRAIN_HOME}}|$FAKE_SB_HOME|g" "$SCENARIO_A/settings.json"
rm -f "$SCENARIO_A/settings.json.bak"

# AC3.a — no /Users/eduardodidio/ literal anywhere.
count_a="$(grep -c '/Users/eduardodidio/' "$SCENARIO_A/settings.json" || true)"
[ "$count_a" -eq 0 ] \
  && pass "yes-branch: no /Users/eduardodidio/ literal" \
  || fail "yes-branch: /Users/eduardodidio/ still present ($count_a occurrences)"

# AC3.b — no leftover placeholders.
if grep -qE '\{\{DIDIO_(HOME|SECOND_BRAIN_HOME)\}\}' "$SCENARIO_A/settings.json"; then
  fail "yes-branch: leftover placeholder in materialized file"
else
  pass "yes-branch: no leftover placeholders"
fi

# AC3.c — resolved paths actually present.
grep -q "$FAKE_DIDIO_HOME/bin/hooks/didio-pre-tool.sh" "$SCENARIO_A/settings.json" \
  && grep -q "$FAKE_SB_HOME/patterns/hooks/stop-session-summary/hook.sh" "$SCENARIO_A/settings.json" \
  && pass "yes-branch: both resolved paths present" \
  || fail "yes-branch: expected resolved paths missing"

# AC3.d — JSON still valid.
python3 -c "import json; json.load(open('$SCENARIO_A/settings.json'))" 2>/dev/null \
  && pass "yes-branch: JSON valid" \
  || fail "yes-branch: JSON invalid after substitution"

# ---------------------------------------------------------------------------
# Scenario B — no-branch (user declines second-brain).
#   Simulates: skill substitutes DIDIO_HOME, then strips hook entries that
#   still contain {{DIDIO_SECOND_BRAIN_HOME}} via python3.
# ---------------------------------------------------------------------------
SCENARIO_B="$SANDBOX/no/.claude"
mkdir -p "$SCENARIO_B"
cp "$TEMPLATE" "$SCENARIO_B/settings.json"

sed -i.bak "s|{{DIDIO_HOME}}|$FAKE_DIDIO_HOME|g" "$SCENARIO_B/settings.json"
rm -f "$SCENARIO_B/settings.json.bak"

python3 - "$SCENARIO_B/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
with open(p) as f: s = json.load(f)
for key in ('Stop', 'SubagentStop', 'PostToolUse'):
    for entry in s.get('hooks', {}).get(key, []):
        entry['hooks'] = [
            h for h in entry.get('hooks', [])
            if '{{DIDIO_SECOND_BRAIN_HOME}}' not in h.get('command', '')
        ]
with open(p, 'w') as f:
    json.dump(s, f, indent=2)
PY

# AC4.a — no /Users/eduardodidio/ literal.
count_b="$(grep -c '/Users/eduardodidio/' "$SCENARIO_B/settings.json" || true)"
[ "$count_b" -eq 0 ] \
  && pass "no-branch: no /Users/eduardodidio/ literal" \
  || fail "no-branch: /Users/eduardodidio/ still present ($count_b)"

# AC4.b — no SECOND_BRAIN hook commands left.
if grep -q 'DIDIO_SECOND_BRAIN_HOME' "$SCENARIO_B/settings.json"; then
  fail "no-branch: SECOND_BRAIN reference remained after strip"
else
  pass "no-branch: SECOND_BRAIN hook entries stripped"
fi

# AC4.c — DIDIO_HOME framework hooks ARE preserved.
grep -q "$FAKE_DIDIO_HOME/bin/hooks/didio-pre-tool.sh" "$SCENARIO_B/settings.json" \
  && grep -q "$FAKE_DIDIO_HOME/bin/hooks/didio-post-tool.sh" "$SCENARIO_B/settings.json" \
  && pass "no-branch: didio framework hooks preserved" \
  || fail "no-branch: didio framework hooks accidentally stripped"

# AC4.d — JSON still valid.
python3 -c "import json; json.load(open('$SCENARIO_B/settings.json'))" 2>/dev/null \
  && pass "no-branch: JSON valid" \
  || fail "no-branch: JSON invalid after strip"

if [ "$FAIL" -ne 0 ]; then
  echo "----"
  echo "F24-skill-materialization.sh: FAILED"
  exit 1
fi
echo "----"
echo "F24-skill-materialization.sh: ALL PASS"
