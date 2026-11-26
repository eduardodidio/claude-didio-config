#!/usr/bin/env bash
# F33 DOB Smoke Test — validates runner, scorer, and regression gate end-to-end
set -euo pipefail

DIDIO_HOME="$(cd "$(dirname "$0")/.." && pwd)"
export DIDIO_HOME
cd "$DIDIO_HOME"

PASS=0
FAIL=0
report() { if [[ "$1" == "PASS" ]]; then ((PASS++)); else ((FAIL++)); fi; echo "  [$1] $2"; }

echo "=== F33 DOB Smoke Test ==="

# --- 1. Config validation ---
echo ""
echo "--- 1. Config validation ---"
python3 -c "import json; c=json.load(open('didio.config.json')); assert 'dob' in c; print('dob block present')" 2>/dev/null \
  && report PASS "dob config block exists" \
  || report FAIL "dob config block missing"

python3 -c "import json; c=json.load(open('didio.config.json')); assert c['dob']['k']==3" 2>/dev/null \
  && report PASS "dob.k = 3" \
  || report FAIL "dob.k != 3"

# --- 2. Dimensions schema ---
echo ""
echo "--- 2. Dimensions schema ---"
python3 -c "
import json
d = json.load(open('docs/dob-dimensions.json'))
assert len(d['dimensions']) == 12
for dim in d['dimensions']:
    for key in ['id','name','description','weight','range','rubric']:
        assert key in dim, f'missing {key} in {dim[\"id\"]}'
print('12 dimensions, all fields present')
" 2>/dev/null \
  && report PASS "dimensions schema valid (12 dims)" \
  || report FAIL "dimensions schema invalid"

# --- 3. Runner ---
echo ""
echo "--- 3. Runner ---"
bash -n bin/didio-dob-runner.sh \
  && report PASS "runner syntax OK" \
  || report FAIL "runner syntax error"

TMPRESULTS=$(mktemp -d)
trap "rm -rf $TMPRESULTS" EXIT

# Override results dir
DOB_ORIG_RESULTS=$(python3 -c "import json; print(json.load(open('didio.config.json')).get('dob',{}).get('results_dir','logs/dob-results'))")
# Run with K=2 for speed, writing to temp
bin/didio-dob-runner.sh --fixture example --k 2 > /dev/null 2>&1 \
  && report PASS "runner executes with K=2" \
  || report FAIL "runner failed"

# Find latest results
LATEST=$(ls -d logs/dob-results/example/2026* 2>/dev/null | tail -1)
if [[ -n "$LATEST" && -f "$LATEST/run-1/metrics.json" && -f "$LATEST/run-2/metrics.json" ]]; then
  report PASS "runner produced 2 run dirs with metrics.json"
else
  report FAIL "runner did not produce expected run dirs"
fi

# --- 4. Scorer ---
echo ""
echo "--- 4. Scorer ---"
bash -n bin/didio-dob-scorer.sh \
  && report PASS "scorer syntax OK" \
  || report FAIL "scorer syntax error"

if [[ -n "$LATEST" ]]; then
  bin/didio-dob-scorer.sh "$LATEST" > /dev/null 2>&1 \
    && report PASS "scorer produces summary.json" \
    || report FAIL "scorer failed"

  if [[ -f "$LATEST/summary.json" ]]; then
    python3 -c "
import json
s = json.load(open('$LATEST/summary.json'))
assert s['k'] == 2
assert len(s['dimensions']) == 12
assert s['overall_score'] > 0
assert s['overall_max'] == 120.0
print(f'overall: {s[\"overall_score\"]}/{s[\"overall_max\"]}')
" 2>/dev/null \
      && report PASS "summary.json structure valid" \
      || report FAIL "summary.json structure invalid"
  fi
fi

# --- 5. Regression gate ---
echo ""
echo "--- 5. Regression gate ---"
bash -n bin/didio-dob-regression.sh \
  && report PASS "regression syntax OK" \
  || report FAIL "regression syntax error"

if [[ -n "$LATEST" && -f "$LATEST/summary.json" ]]; then
  # Same vs same -> PASS
  bin/didio-dob-regression.sh "$LATEST/summary.json" "$LATEST/summary.json" > /dev/null 2>&1 \
    && report PASS "regression: same vs same = PASS" \
    || report FAIL "regression: same vs same should PASS"
fi

# --- 6. CLI wiring ---
echo ""
echo "--- 6. CLI wiring ---"
grep -q 'dob-run' bin/didio && report PASS "dob-run wired in CLI" || report FAIL "dob-run missing from CLI"
grep -q 'dob-score' bin/didio && report PASS "dob-score wired in CLI" || report FAIL "dob-score missing from CLI"
grep -q 'dob-regression' bin/didio && report PASS "dob-regression wired in CLI" || report FAIL "dob-regression missing from CLI"

# --- Summary ---
echo ""
TOTAL=$((PASS + FAIL))
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]] && echo "PASS: DOB smoke test" || echo "FAIL: DOB smoke test"
exit $FAIL
