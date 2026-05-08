#!/usr/bin/env bash
# F22 end-to-end smoke test. No internet, no real claude binary, no real API key.
# Run: bash /Users/eduardodidio/claude-didio-config/tests/F22-e2e-smoke.sh
set -uo pipefail

DIDIO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DIDIO_HOME

FIX_DIR="$DIDIO_HOME/tests/F22-fixtures"
SANDBOX=$(mktemp -d -t f22-e2e-XXXX)
trap 'rm -rf "$SANDBOX"' EXIT

# ── Sandbox project structure ────────────────────────────────────────────────
mkdir -p "$SANDBOX/tasks/features/F22T-mock" \
         "$SANDBOX/agents/prompts" \
         "$SANDBOX/logs/agents/_pending"

cat > "$SANDBOX/tasks/features/F22T-mock/F22T-README.md" <<'RDME'
# F22T mock
- **Wave 1**: F22T-T01, F22T-T02
RDME
echo "# task" > "$SANDBOX/tasks/features/F22T-mock/F22T-T01.md"
echo "# task" > "$SANDBOX/tasks/features/F22T-mock/F22T-T02.md"
echo "# developer prompt" > "$SANDBOX/agents/prompts/developer.md"

cd "$SANDBOX"

export DIDIO_RATE_LIMIT_MARGIN_SEC=1
export DIDIO_MAX_RETRIES=3
unset ANTHROPIC_API_KEY 2>/dev/null || true

pass=0; fail=0
assert() {
  local label="$1" cond="$2"
  if eval "$cond" 2>/dev/null; then
    echo "PASS: $label"; pass=$((pass+1))
  else
    echo "FAIL: $label"; fail=$((fail+1))
  fi
}

# ── Scenario 1: schedule mode produces pending json ──────────────────────────
rm -rf logs/agents/_pending && mkdir -p logs/agents/_pending
rc=0
MOCK_CLAUDE_FIXTURE=rate-limit-brt-am.jsonl MOCK_CLAUDE_EXIT=1 \
  PATH="$FIX_DIR/bin:$PATH" \
  DIDIO_ON_RATE_LIMIT=schedule \
  bash "$DIDIO_HOME/bin/didio-spawn-agent.sh" developer F22T \
    tasks/features/F22T-mock/F22T-T01.md "" || rc=$?
assert "schedule mode exits 2" \
  "[[ $rc -eq 2 ]]"
assert "schedule mode writes pending json" \
  "ls logs/agents/_pending/F22T-developer-F22T-T01-*.json >/dev/null 2>&1"
assert "pending json has schema_version=1" \
  "python3 -c \"import json,glob; f=glob.glob('logs/agents/_pending/F22T-developer-F22T-T01-*.json')[0]; d=json.load(open(f)); assert d['schema_version']==1\""

# ── Scenario 2: fail-fast mode — no pending file ─────────────────────────────
rm -rf logs/agents/_pending && mkdir -p logs/agents/_pending
rc=0
MOCK_CLAUDE_FIXTURE=rate-limit-brt-am.jsonl MOCK_CLAUDE_EXIT=1 \
  PATH="$FIX_DIR/bin:$PATH" \
  DIDIO_ON_RATE_LIMIT=fail-fast \
  bash "$DIDIO_HOME/bin/didio-spawn-agent.sh" developer F22T \
    tasks/features/F22T-mock/F22T-T01.md "" || rc=$?
assert "fail-fast exits 1" \
  "[[ $rc -eq 1 ]]"
pend_count_s2=0
shopt -s nullglob
for _f in logs/agents/_pending/*.json; do pend_count_s2=$((pend_count_s2+1)); done
shopt -u nullglob
assert "fail-fast writes no pending file" \
  "[[ $pend_count_s2 -eq 0 ]]"

# ── Scenario 3: wait mode — sleeps 0s (margin cancels out future reset) ──────
# Generate a reset time 2 hours from now in UTC (guaranteed future from the
# lib's perspective). Set DIDIO_RATE_LIMIT_MARGIN_SEC=-86400 so that
# SLEEP_FOR = (now+2h) - now + (-86400) < 0 → clamped to 0. No real sleep.
RESET_TIME=$(python3 -c "
from datetime import datetime, timedelta, timezone
t = datetime.now(timezone.utc) + timedelta(hours=2)
print(t.strftime('%I:%M%p (UTC)').lstrip('0').lower())
")
SYNTH="$SANDBOX/synth-rl.jsonl"
cat > "$SYNTH" <<JSONL
{"type":"system","subtype":"init","model":"claude"}
{"type":"result","subtype":"success","is_error":true,"result":"You've hit your limit · resets ${RESET_TIME}","duration_ms":100,"num_turns":0,"total_cost_usd":0,"usage":{}}
JSONL

# Stateful mock: call 1 → rate-limit JSONL; call 2 → success JSONL
MOCK2="$SANDBOX/mock2/claude"
mkdir -p "$SANDBOX/mock2"
# Use double-quoted heredoc: $SANDBOX, $SYNTH, $FIX_DIR expand NOW;
# \$, \${...}, \$((...)) become runtime bash expressions in the written script.
cat > "$MOCK2" <<EOF
#!/usr/bin/env bash
STATE_FILE="${SANDBOX}/.mock2-state"
COUNT=\$(cat "\${STATE_FILE}" 2>/dev/null || echo 0)
COUNT=\$((COUNT+1))
echo "\$COUNT" > "\${STATE_FILE}"
if [[ \$COUNT -eq 1 ]]; then cat "${SYNTH}"; exit 1
else cat "${FIX_DIR}/success.jsonl"; exit 0
fi
EOF
chmod +x "$MOCK2"

rm -rf logs/agents/_pending && mkdir -p logs/agents/_pending
rc=0
PATH="$SANDBOX/mock2:$PATH" \
  DIDIO_ON_RATE_LIMIT=wait \
  DIDIO_RATE_LIMIT_MARGIN_SEC=-86400 \
  bash "$DIDIO_HOME/bin/didio-spawn-agent.sh" developer F22T \
    tasks/features/F22T-mock/F22T-T01.md "" || rc=$?
assert "wait mode eventually exits 0" \
  "[[ $rc -eq 0 ]]"
assert "wait mode wrote resume telemetry to index.jsonl" \
  "grep -q 'resume' logs/agents/_pending/index.jsonl"

# ── Scenario 4: run-wave defers remaining tasks on rate-limit ────────────────
rm -rf logs/agents/_pending && mkdir -p logs/agents/_pending
rc=0
PATH="$FIX_DIR/bin:$PATH" \
  MOCK_CLAUDE_FIXTURE=rate-limit-brt-am.jsonl MOCK_CLAUDE_EXIT=1 \
  DIDIO_ON_RATE_LIMIT=schedule \
  bash "$DIDIO_HOME/bin/didio-run-wave.sh" F22T 1 developer || rc=$?
assert "run-wave exits 2 on rate-limit" \
  "[[ $rc -eq 2 ]]"
pend_count_s4=0
shopt -s nullglob
for _f in logs/agents/_pending/*.json; do pend_count_s4=$((pend_count_s4+1)); done
shopt -u nullglob
assert "run-wave wrote ≥2 pending files" \
  "[[ $pend_count_s4 -ge 2 ]]"

# ── Scenario 5: resume-pending dry-run ───────────────────────────────────────
rc=0
DR_OUT=$(bash "$DIDIO_HOME/bin/didio-resume-pending.sh" --dry-run --all-future 2>&1) || rc=$?
dr_has_dryrun=0; echo "$DR_OUT" | grep -q 'dry-run' && dr_has_dryrun=1 || true
assert "dry-run output mentions 'dry-run'" \
  "[[ $dr_has_dryrun -eq 1 ]]"
pend_count_s5=0
shopt -s nullglob
for _f in logs/agents/_pending/*.json; do pend_count_s5=$((pend_count_s5+1)); done
shopt -u nullglob
assert "dry-run does not consume pending files" \
  "[[ $pend_count_s5 -eq $pend_count_s4 ]]"

# ── Scenario 6: classifier coverage ─────────────────────────────────────────
# Source lib for direct function access; set +e so test-runner can catch fails.
# shellcheck disable=SC1090
source "$DIDIO_HOME/bin/didio-rate-limit-lib.sh"
set +e

for fx in rate-limit-brt-am rate-limit-est-pm rate-limit-utc-24h; do
  cls=$(didio_rl_classify_jsonl "$FIX_DIR/${fx}.jsonl")
  assert "classify ${fx} == rate_limit" "[[ '$cls' = 'rate_limit' ]]"
done
cls=$(didio_rl_classify_jsonl "$FIX_DIR/success.jsonl")
assert "classify success.jsonl == success"      "[[ '$cls' = 'success' ]]"
cls=$(didio_rl_classify_jsonl "$FIX_DIR/real-error.jsonl")
assert "classify real-error.jsonl == real_error" "[[ '$cls' = 'real_error' ]]"
cls=$(didio_rl_classify_jsonl "$FIX_DIR/unknown-no-result.jsonl")
assert "classify unknown-no-result.jsonl == unknown" "[[ '$cls' = 'unknown' ]]"

# ── Summary ──────────────────────────────────────────────────────────────────
echo "------"
echo "F22 e2e: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
