#!/usr/bin/env bash
# F33 Integration Test — full DOB validation + BMAD purge verification
set -euo pipefail

DIDIO_HOME="$(cd "$(dirname "$0")/.." && pwd)"
export DIDIO_HOME
cd "$DIDIO_HOME"

PASS=0
FAIL=0
report() { if [[ "$1" == "PASS" ]]; then ((PASS++)); else ((FAIL++)); fi; echo "  [$1] $2"; }

echo "=== F33 Integration Test ==="

# --- 1. DOB Config ---
echo ""
echo "--- 1. DOB Config ---"
python3 -c "
import json
c = json.load(open('didio.config.json'))
dob = c['dob']
assert dob['k'] == 3
assert dob['fixtures_dir'] == 'tests/dob-fixtures'
assert dob['results_dir'] == 'logs/dob-results'
assert dob['regression']['threshold_pct'] == 10
print('config OK')
" 2>/dev/null && report PASS "DOB config complete" || report FAIL "DOB config incomplete"

python3 -c "
import json
c = json.load(open('templates/didio.config.json'))
assert 'dob' in c
print('template OK')
" 2>/dev/null && report PASS "DOB template config present" || report FAIL "DOB template config missing"

# --- 2. Dimensions Schema ---
echo ""
echo "--- 2. Dimensions Schema ---"
python3 -c "
import json
d = json.load(open('docs/dob-dimensions.json'))
assert len(d['dimensions']) == 12
ids = [dim['id'] for dim in d['dimensions']]
expected = ['task_decomposition','parallel_efficiency','context_isolation','token_efficiency',
            'test_coverage_delta','diagram_accuracy','guardrail_compliance','recovery_resilience',
            'learning_retention','pipeline_autonomy','time_to_feature','rework_rate']
for e in expected:
    assert e in ids, f'missing dimension: {e}'
print('all 12 dimensions present')
" 2>/dev/null && report PASS "12 dimensions with correct IDs" || report FAIL "dimension IDs mismatch"

# --- 3. Run all fixtures ---
echo ""
echo "--- 3. Run all fixtures ---"
for fixture in example baseline-v1 degraded minimal; do
  bin/didio-dob-runner.sh --fixture "$fixture" --k 1 > /dev/null 2>&1 \
    && report PASS "runner: $fixture K=1" \
    || report FAIL "runner: $fixture failed"
done

# --- 4. Score all fixtures ---
echo ""
echo "--- 4. Score all fixtures ---"
for fixture in example baseline-v1 degraded minimal; do
  LATEST=$(ls -d logs/dob-results/$fixture/2026* 2>/dev/null | tail -1)
  if [[ -n "$LATEST" ]]; then
    bin/didio-dob-scorer.sh "$LATEST" > /dev/null 2>&1 \
      && report PASS "scorer: $fixture" \
      || report FAIL "scorer: $fixture failed"
  else
    report FAIL "scorer: no results for $fixture"
  fi
done

# --- 5. Regression gate ---
echo ""
echo "--- 5. Regression gate ---"
BASELINE_DIR=$(ls -d logs/dob-results/baseline-v1/2026* 2>/dev/null | tail -1)
DEGRADED_DIR=$(ls -d logs/dob-results/degraded/2026* 2>/dev/null | tail -1)

if [[ -n "$BASELINE_DIR" && -n "$DEGRADED_DIR" ]]; then
  # baseline vs degraded -> should FAIL
  if bin/didio-dob-regression.sh "$BASELINE_DIR/summary.json" "$DEGRADED_DIR/summary.json" > /dev/null 2>&1; then
    report FAIL "regression: baseline vs degraded should FAIL"
  else
    report PASS "regression: baseline vs degraded = FAIL (expected)"
  fi

  # baseline vs baseline -> should PASS
  bin/didio-dob-regression.sh "$BASELINE_DIR/summary.json" "$BASELINE_DIR/summary.json" > /dev/null 2>&1 \
    && report PASS "regression: baseline vs baseline = PASS" \
    || report FAIL "regression: baseline vs baseline should PASS"
fi

# --- 6. BMAD Purge ---
echo ""
echo "--- 6. BMAD Purge ---"

# No operational BMAD refs in edited files
BMAD_HITS=$(grep -ri 'bmad' agents/prompts/tea.md skills/tea.md templates/agents/prompts/tea.md templates/commands/didio.md templates/.claude/commands/didio.md 2>/dev/null | grep -iv 'historical\|reference\|inspiration\|credit' | wc -l || true)
[[ "$BMAD_HITS" -eq 0 ]] \
  && report PASS "no operational BMAD refs in edited files" \
  || report FAIL "$BMAD_HITS operational BMAD refs remain"

# F27 test files deleted
F27_COUNT=$(ls bin/tests/F27-*.sh 2>/dev/null | wc -l || true)
[[ "$F27_COUNT" -eq 0 ]] \
  && report PASS "F27 test files deleted" \
  || report FAIL "$F27_COUNT F27 test files remain"

# Historical docs preserved
for doc in docs/bmad-integration-plan.md docs/F27-bmad-mode.md claude_didio_config_vs_bmad.md; do
  [[ -f "$doc" ]] \
    && report PASS "historical doc preserved: $doc" \
    || report FAIL "historical doc missing: $doc"
done

# --- 7. CLI wiring ---
echo ""
echo "--- 7. CLI wiring ---"
bash -n bin/didio && report PASS "bin/didio syntax OK" || report FAIL "bin/didio syntax error"
for cmd in dob-run dob-score dob-regression; do
  grep -q "$cmd" bin/didio && report PASS "CLI: $cmd wired" || report FAIL "CLI: $cmd missing"
done

# --- 8. Docs and diagrams ---
echo ""
echo "--- 8. Docs and diagrams ---"
[[ -f docs/dob-protocol.md ]] && report PASS "protocol doc exists" || report FAIL "protocol doc missing"
[[ -f docs/adr/0011-dob-benchmark-bmad-purge.md ]] && report PASS "ADR-0011 exists" || report FAIL "ADR-0011 missing"
[[ -f docs/diagrams/F33-architecture.mmd ]] && report PASS "architecture diagram exists" || report FAIL "architecture diagram missing"
[[ -f docs/diagrams/F33-journey.mmd ]] && report PASS "journey diagram exists" || report FAIL "journey diagram missing"

# --- Summary ---
echo ""
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && echo "PASS: F33 integration test" || echo "FAIL: F33 integration test"
exit $FAIL
