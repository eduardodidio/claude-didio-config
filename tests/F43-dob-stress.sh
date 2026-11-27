#!/usr/bin/env bash
# F43-T03 — DOB Benchmark Stress Test Suite
# Comprehensive edge-case and stress tests for the DOB benchmark system.
# Output: TAP protocol (Test Anything Protocol)
# Usage: bash tests/F43-dob-stress.sh
set -uo pipefail

# ---------------------------------------------------------------------------
# Setup — project root, temp workspace, cleanup trap
# ---------------------------------------------------------------------------
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# On MINGW64/Git Bash, mktemp returns /tmp/... paths that Python cannot
# resolve. Convert to mixed paths (C:/...) that work for both bash and Python.
to_native() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$1"
  else
    echo "$1"
  fi
}

TMPDIR_RAW=$(mktemp -d)
TMPDIR_BASE=$(to_native "$TMPDIR_RAW")
WORK="$TMPDIR_BASE/dob-stress"
mkdir -p "$WORK"

PROJECT_ROOT=$(to_native "$PROJECT_ROOT")

cleanup() {
  rm -rf "$TMPDIR_RAW"
}
trap cleanup EXIT

# Script paths (use native paths for Python compatibility)
RUNNER="$PROJECT_ROOT/bin/didio-dob-runner.sh"
SCORER="$PROJECT_ROOT/bin/didio-dob-scorer.sh"
REGRESSION="$PROJECT_ROOT/bin/didio-dob-regression.sh"

# TAP state
TESTS=0
FAILURES=0

tap_ok() {
  TESTS=$((TESTS + 1))
  echo "ok $TESTS - $1"
}

tap_fail() {
  TESTS=$((TESTS + 1))
  FAILURES=$((FAILURES + 1))
  echo "not ok $TESTS - $1"
  if [[ -n "${2:-}" ]]; then
    # TAP diagnostic: indent each line with #
    echo "$2" | while IFS= read -r line; do echo "# $line"; done
  fi
}

# ---------------------------------------------------------------------------
# Helper: create a minimal isolated workspace so the DOB scripts read the
# right config and dimensions schema from the cwd.
# Args: $1 = workspace dir to initialise
# ---------------------------------------------------------------------------
init_workspace() {
  local ws="$1"
  mkdir -p "$ws/tests/dob-fixtures" "$ws/docs" "$ws/logs/dob-results"

  # Minimal didio.config.json
  cat > "$ws/didio.config.json" <<'JSON'
{
  "dob": {
    "enabled": true,
    "k": 3,
    "fixtures_dir": "tests/dob-fixtures",
    "results_dir": "logs/dob-results",
    "dimensions_schema": "docs/dob-dimensions.json",
    "regression": {
      "threshold_pct": 10,
      "block_on_regression": true
    }
  }
}
JSON

  # Copy the real dimensions schema
  cp "$PROJECT_ROOT/docs/dob-dimensions.json" "$ws/docs/dob-dimensions.json"
}

# ---------------------------------------------------------------------------
# Helper: create a fixture JSON with uniform values across all 12 dimensions.
# Args: $1=ws $2=fixture-name $3=comma-separated-values (e.g. "7,7,7")
# ---------------------------------------------------------------------------
create_uniform_fixture() {
  local ws="$1" name="$2" values_csv="$3"
  python3 -c "
import json, os
os.chdir('$ws')
schema = json.load(open('docs/dob-dimensions.json'))
ids = [d['id'] for d in schema['dimensions']]
metrics = {}
for d in ids:
    metrics[d] = {'values': [$values_csv]}
fixture = {'name': '$name', 'metrics': metrics}
with open('tests/dob-fixtures/${name}.json', 'w') as f:
    json.dump(fixture, f, indent=2)
"
}

# ---------------------------------------------------------------------------
# Helper: create a fixture JSON with specific per-dimension values.
# Args: $1=ws $2=fixture-name $3=python-dict-literal for metrics
# ---------------------------------------------------------------------------
create_custom_fixture() {
  local ws="$1" name="$2" metrics_py="$3"
  python3 -c "
import json
metrics = $metrics_py
fixture = {'name': '$name', 'metrics': metrics}
with open('$ws/tests/dob-fixtures/${name}.json', 'w') as f:
    json.dump(fixture, f, indent=2)
"
}

# ---------------------------------------------------------------------------
# Helper: run runner+scorer in a workspace, return results dir path.
# Args: $1=ws $2=fixture-name $3=k
# Echoes the results directory path on stdout.
# ---------------------------------------------------------------------------
run_and_score() {
  local ws="$1" name="$2" k="$3"
  (
    cd "$ws"
    bash "$RUNNER" --fixture "$name" --k "$k" >/dev/null 2>&1
  )
  local results_dir
  results_dir=$(ls -d "$ws/logs/dob-results/$name/"* 2>/dev/null | tail -1)
  if [[ -z "$results_dir" ]]; then
    echo ""
    return 1
  fi
  (
    cd "$ws"
    # Make path relative for scorer (it reads config from cwd)
    local rel="${results_dir#$ws/}"
    bash "$SCORER" "$rel" >/dev/null 2>&1
  )
  echo "$results_dir"
}

# ---------------------------------------------------------------------------
# Helper: create a summary.json directly (for regression tests).
# Args: $1=file-path $2=mean-value-for-all-dims
# ---------------------------------------------------------------------------
write_summary() {
  local path="$1" mean_val="$2"
  python3 -c "
import json
dims = {}
dim_ids = ['task_decomposition','parallel_efficiency','context_isolation',
           'token_efficiency','test_coverage_delta','diagram_accuracy',
           'guardrail_compliance','recovery_resilience','learning_retention',
           'pipeline_autonomy','time_to_feature','rework_rate']
for d in dim_ids:
    dims[d] = {'mean': $mean_val, 'stddev': 0.0, 'min': $mean_val, 'max': $mean_val, 'weight': 1.0, 'weighted_score': $mean_val}
summary = {'fixture':'test','k':1,'dimensions':dims,'overall_score':$mean_val*12,'overall_max':120.0}
with open('$path','w') as f:
    json.dump(summary, f, indent=2)
"
}

# ---------------------------------------------------------------------------
# Helper: check a Python assertion on a summary.json
# Args: $1=summary-path $2=python-assertion-code
# Returns: "OK" on success, error text on failure
# ---------------------------------------------------------------------------
check_summary() {
  local spath="$1" code="$2"
  python3 -c "
import json, math, sys
s = json.load(open('$spath'))
$code
print('OK')
" 2>&1
}

# ===========================================================================
echo "# F43-T03: DOB Benchmark Stress Test Suite"

# ===================================================================
# TEST GROUP 1: K Variation
# ===================================================================
echo "# --- K Variation ---"

# T1: K=1 — single run, stddev must be 0
WS1="$WORK/k1"
init_workspace "$WS1"
create_uniform_fixture "$WS1" "k1-test" "7"
RDIR=$(run_and_score "$WS1" "k1-test" 1)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
assert s['k'] == 1, f'k={s[\"k\"]}'
for dim_id, dim in s['dimensions'].items():
    assert dim['stddev'] == 0.0, f'{dim_id} stddev={dim[\"stddev\"]}'
    assert dim['mean'] == 7.0, f'{dim_id} mean={dim[\"mean\"]}'
")
  [[ "$RESULT" == "OK" ]] && tap_ok "K=1: single run, stddev=0, mean=value" \
    || tap_fail "K=1: stddev/mean check failed" "$RESULT"
else
  tap_fail "K=1: runner/scorer did not produce summary.json"
fi

# T2: K=2 — two runs, verify mean and stddev
WS2="$WORK/k2"
init_workspace "$WS2"
create_uniform_fixture "$WS2" "k2-test" "6, 8"
RDIR=$(run_and_score "$WS2" "k2-test" 2)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
assert s['k'] == 2
for dim_id, dim in s['dimensions'].items():
    assert dim['mean'] == 7.0, f'{dim_id} mean={dim[\"mean\"]}'
    assert dim['stddev'] == 1.0, f'{dim_id} stddev={dim[\"stddev\"]}'
")
  [[ "$RESULT" == "OK" ]] && tap_ok "K=2: two runs, correct mean=7 and stddev=1" \
    || tap_fail "K=2: mean/stddev check failed" "$RESULT"
else
  tap_fail "K=2: runner/scorer failed"
fi

# T3: K=5 — verify 5 run dirs created with metrics.json
WS5="$WORK/k5"
init_workspace "$WS5"
create_uniform_fixture "$WS5" "k5-test" "5, 6, 7, 8, 9"
RDIR=$(run_and_score "$WS5" "k5-test" 5)
if [[ -n "$RDIR" ]]; then
  COUNT=$(ls "$RDIR"/run-*/metrics.json 2>/dev/null | wc -l)
  COUNT=$(echo "$COUNT" | tr -d ' ')
  if [[ "$COUNT" -eq 5 ]]; then
    tap_ok "K=5: five run dirs with metrics.json"
  else
    tap_fail "K=5: expected 5 run dirs, got $COUNT"
  fi
else
  tap_fail "K=5: runner failed"
fi

# ===================================================================
# TEST GROUP 2: Score Boundaries
# ===================================================================
echo "# --- Score Boundaries ---"

# T4: All zeros [0,0,0] => mean=0
WS_Z="$WORK/zeros"
init_workspace "$WS_Z"
create_uniform_fixture "$WS_Z" "all-zeros" "0, 0, 0"
RDIR=$(run_and_score "$WS_Z" "all-zeros" 3)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
assert s['overall_score'] == 0.0, f'overall={s[\"overall_score\"]}'
for dim_id, dim in s['dimensions'].items():
    assert dim['mean'] == 0.0, f'{dim_id} mean={dim[\"mean\"]}'
")
  [[ "$RESULT" == "OK" ]] && tap_ok "Score boundary: all zeros => mean=0, overall=0" \
    || tap_fail "Score boundary: all zeros" "$RESULT"
else
  tap_fail "Score boundary: all zeros runner failed"
fi

# T5: All tens [10,10,10] => mean=10
WS_T="$WORK/tens"
init_workspace "$WS_T"
create_uniform_fixture "$WS_T" "all-tens" "10, 10, 10"
RDIR=$(run_and_score "$WS_T" "all-tens" 3)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
assert s['overall_score'] == 120.0, f'overall={s[\"overall_score\"]}'
for dim_id, dim in s['dimensions'].items():
    assert dim['mean'] == 10.0, f'{dim_id} mean={dim[\"mean\"]}'
")
  [[ "$RESULT" == "OK" ]] && tap_ok "Score boundary: all tens => mean=10, overall=120" \
    || tap_fail "Score boundary: all tens" "$RESULT"
else
  tap_fail "Score boundary: all tens runner failed"
fi

# T6: Mixed extremes [0,10,5] => mean=5, stddev~4.08
WS_M="$WORK/mixed"
init_workspace "$WS_M"
create_uniform_fixture "$WS_M" "mixed" "0, 10, 5"
RDIR=$(run_and_score "$WS_M" "mixed" 3)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
expected_stddev = round(math.sqrt(50.0/3.0), 2)
for dim_id, dim in s['dimensions'].items():
    assert dim['mean'] == 5.0, f'{dim_id} mean={dim[\"mean\"]}'
    assert dim['stddev'] == expected_stddev, f'{dim_id} stddev={dim[\"stddev\"]} expected={expected_stddev}'
")
  [[ "$RESULT" == "OK" ]] && tap_ok "Score boundary: mixed [0,10,5] => mean=5, stddev=4.08" \
    || tap_fail "Score boundary: mixed extremes" "$RESULT"
else
  tap_fail "Score boundary: mixed runner failed"
fi

# ===================================================================
# TEST GROUP 3: Regression Threshold Boundary
# ===================================================================
echo "# --- Regression Threshold Boundary ---"

# T7: Regression exactly at -10% boundary => PASS
# baseline=8, current=7.2 => delta = (7.2-8)/8 * 100 = -10.0%
# Code: delta_pct < -threshold => -10.0 < -10 => False => PASS
WS_R1="$WORK/reg-exact"
init_workspace "$WS_R1"
write_summary "$WS_R1/baseline.json" 8.0
write_summary "$WS_R1/current.json" 7.2
(cd "$WS_R1" && bash "$REGRESSION" baseline.json current.json --threshold 10 >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 0 ]]; then
  tap_ok "Regression boundary: -10% exactly => PASS (not beyond threshold)"
else
  tap_fail "Regression boundary: -10% exactly should PASS, got exit=$RC"
fi

# T8: Regression at -10.125% => FAIL
# baseline=8, current=7.19 => delta = (7.19-8)/8 * 100 = -10.125%
# -10.125 < -10 => True => FAIL
WS_R2="$WORK/reg-fail"
init_workspace "$WS_R2"
write_summary "$WS_R2/baseline.json" 8.0
write_summary "$WS_R2/current.json" 7.19
(cd "$WS_R2" && bash "$REGRESSION" baseline.json current.json --threshold 10 >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 1 ]]; then
  tap_ok "Regression boundary: -10.125% => FAIL (beyond threshold)"
else
  tap_fail "Regression boundary: -10.125% should FAIL (exit 1), got exit=$RC"
fi

# T9: Regression at -9.9% => PASS
# baseline=10, current=9.01 => delta = (9.01-10)/10 * 100 = -9.9%
WS_R3="$WORK/reg-pass"
init_workspace "$WS_R3"
write_summary "$WS_R3/baseline.json" 10.0
write_summary "$WS_R3/current.json" 9.01
(cd "$WS_R3" && bash "$REGRESSION" baseline.json current.json --threshold 10 >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 0 ]]; then
  tap_ok "Regression boundary: -9.9% => PASS (within threshold)"
else
  tap_fail "Regression boundary: -9.9% should PASS, got exit=$RC"
fi

# ===================================================================
# TEST GROUP 4: Zero Baseline
# ===================================================================
echo "# --- Zero Baseline ---"

# T10: baseline=0, current=5 => no regression (delta=+100%)
WS_ZB1="$WORK/zero-base1"
init_workspace "$WS_ZB1"
write_summary "$WS_ZB1/baseline.json" 0.0
write_summary "$WS_ZB1/current.json" 5.0
(cd "$WS_ZB1" && bash "$REGRESSION" baseline.json current.json --threshold 10 >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 0 ]]; then
  tap_ok "Zero baseline: baseline=0, current=5 => PASS (improvement)"
else
  tap_fail "Zero baseline: baseline=0, current=5 should PASS, got exit=$RC"
fi

# T11: baseline=0, current=0 => no regression (delta=0%)
WS_ZB2="$WORK/zero-both"
init_workspace "$WS_ZB2"
write_summary "$WS_ZB2/baseline.json" 0.0
write_summary "$WS_ZB2/current.json" 0.0
(cd "$WS_ZB2" && bash "$REGRESSION" baseline.json current.json --threshold 10 >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 0 ]]; then
  tap_ok "Zero baseline: baseline=0, current=0 => PASS (no change)"
else
  tap_fail "Zero baseline: both zero should PASS, got exit=$RC"
fi

# ===================================================================
# TEST GROUP 5: Consistency
# ===================================================================
echo "# --- Consistency ---"

# T12: Run same fixture 3 times, compare summary.json — must be identical
WS_C="$WORK/consistency"
init_workspace "$WS_C"
create_uniform_fixture "$WS_C" "consistent" "7, 8, 9"

SUMMARIES=()
for i in 1 2 3; do
  RDIR=$(run_and_score "$WS_C" "consistent" 3)
  if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
    SUMMARIES+=("$RDIR/summary.json")
  fi
  # Small sleep to get different timestamps in dir names
  sleep 1
done

if [[ ${#SUMMARIES[@]} -eq 3 ]]; then
  RESULT=$(python3 -c "
import json
summaries = []
for path in [r'${SUMMARIES[0]}', r'${SUMMARIES[1]}', r'${SUMMARIES[2]}']:
    s = json.load(open(path))
    summaries.append({k: {'mean': v['mean'], 'stddev': v['stddev']} for k, v in s['dimensions'].items()})
assert summaries[0] == summaries[1] == summaries[2], 'Summaries differ!'
print('OK')
" 2>&1)
  [[ "$RESULT" == "OK" ]] && tap_ok "Consistency: 3 runs produce identical scoring" \
    || tap_fail "Consistency: scoring differs across runs" "$RESULT"
else
  tap_fail "Consistency: could not produce 3 summaries (got ${#SUMMARIES[@]})"
fi

# ===================================================================
# TEST GROUP 6: Performance
# ===================================================================
echo "# --- Performance ---"

# T13: K=10 scoring completes in <5 seconds
WS_P="$WORK/perf"
init_workspace "$WS_P"
create_uniform_fixture "$WS_P" "perf-test" "5, 6, 7, 8, 9, 5, 6, 7, 8, 9"

START_TIME=$(date +%s)
RDIR=$(run_and_score "$WS_P" "perf-test" 10)
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  if [[ $ELAPSED -lt 5 ]]; then
    tap_ok "Performance: K=10 scoring completed in ${ELAPSED}s (<5s)"
  else
    tap_fail "Performance: K=10 took ${ELAPSED}s (limit: 5s)"
  fi
else
  tap_fail "Performance: K=10 runner/scorer failed"
fi

# ===================================================================
# TEST GROUP 7: Partial Fixture (fewer than 12 dimensions)
# ===================================================================
echo "# --- Partial Fixture ---"

# T14: Fixture with only 6/12 dimensions — scorer should handle gracefully
# NOTE: The runner iterates schema dim_ids when schema exists, defaulting
# missing dims to value=5. So the scorer sees 12 dims (6 from fixture + 6
# default). This is documented behavior (DOB-004: no strict enforcement).
WS_PF="$WORK/partial"
init_workspace "$WS_PF"
create_custom_fixture "$WS_PF" "partial-6" "{
  'task_decomposition': {'values': [7, 7, 7]},
  'parallel_efficiency': {'values': [8, 8, 8]},
  'context_isolation': {'values': [6, 6, 6]},
  'token_efficiency': {'values': [9, 9, 9]},
  'test_coverage_delta': {'values': [5, 5, 5]},
  'diagram_accuracy': {'values': [4, 4, 4]}
}"
RDIR=$(run_and_score "$WS_PF" "partial-6" 3)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
dim_count = len(s['dimensions'])
assert dim_count >= 6, f'expected >=6 dims, got {dim_count}'
assert s['overall_score'] > 0
")
  if [[ "$RESULT" == "OK" ]]; then
    tap_ok "Partial fixture: 6/12 dimensions handled gracefully"
  else
    tap_fail "Partial fixture: validation failed" "$RESULT"
  fi
else
  tap_fail "Partial fixture: runner/scorer failed"
fi

# ===================================================================
# TEST GROUP 8: Out-of-Range Values
# ===================================================================
echo "# --- Out-of-Range Values ---"

# T15: Values > 10 — DOB-003 says no range validation, so these pass through
WS_OOR="$WORK/oor-high"
init_workspace "$WS_OOR"
create_uniform_fixture "$WS_OOR" "oor-high" "15, 20, 999"
RDIR=$(run_and_score "$WS_OOR" "oor-high" 3)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
for dim_id, dim in s['dimensions'].items():
    assert dim['mean'] > 10, f'{dim_id} mean={dim[\"mean\"]} should be >10'
")
  [[ "$RESULT" == "OK" ]] && tap_ok "Out-of-range: values > 10 pass through (DOB-003)" \
    || tap_fail "Out-of-range: values > 10" "$RESULT"
else
  tap_fail "Out-of-range: runner/scorer failed on high values"
fi

# T16: Values < 0 — also pass through (DOB-003)
WS_OOR2="$WORK/oor-low"
init_workspace "$WS_OOR2"
create_uniform_fixture "$WS_OOR2" "oor-low" "-5, -1, 0"
RDIR=$(run_and_score "$WS_OOR2" "oor-low" 3)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
for dim_id, dim in s['dimensions'].items():
    assert dim['mean'] == -2.0, f'{dim_id} mean={dim[\"mean\"]} expected=-2.0'
")
  [[ "$RESULT" == "OK" ]] && tap_ok "Out-of-range: values < 0 pass through (DOB-003)" \
    || tap_fail "Out-of-range: negative values" "$RESULT"
else
  tap_fail "Out-of-range: runner/scorer failed on negative values"
fi

# ===================================================================
# TEST GROUP 9: Malformed JSON
# ===================================================================
echo "# --- Malformed JSON ---"

# T17: Truncated fixture JSON => runner should fail with clean error
WS_MJ="$WORK/malformed"
init_workspace "$WS_MJ"
echo '{"name": "broken", "metrics": {' > "$WS_MJ/tests/dob-fixtures/malformed.json"
(cd "$WS_MJ" && bash "$RUNNER" --fixture malformed --k 1 >/dev/null 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
  tap_ok "Malformed JSON: truncated fixture produces clean error (exit=$RC)"
else
  tap_fail "Malformed JSON: truncated fixture should fail, got exit=0"
fi

# ===================================================================
# TEST GROUP 10: Empty Values Array
# ===================================================================
echo "# --- Empty Values ---"

# T18: Dimension with values: [] => runner should fail (ZeroDivisionError on modulo)
WS_EV="$WORK/empty-vals"
init_workspace "$WS_EV"
create_custom_fixture "$WS_EV" "empty-vals" "{
  'task_decomposition': {'values': []},
  'parallel_efficiency': {'values': [5]}
}"
(cd "$WS_EV" && bash "$RUNNER" --fixture empty-vals --k 1 >/dev/null 2>&1)
RC=$?
if [[ $RC -ne 0 ]]; then
  tap_ok "Empty values: dimension with values=[] causes error (exit=$RC)"
else
  tap_fail "Empty values: expected error on empty values array, got exit=0"
fi

# ===================================================================
# TEST GROUP 11: Degraded vs Baseline — Regression Gate Catches All
# ===================================================================
echo "# --- Degraded vs Baseline ---"

# T19: Baseline all dims=8, degraded all dims=5.
# delta = (5-8)/8*100 = -37.5% per dimension => all 12 should be flagged.
WS_D="$WORK/degraded"
init_workspace "$WS_D"
write_summary "$WS_D/baseline.json" 8.0
write_summary "$WS_D/degraded.json" 5.0

# Capture JSON output (stdout) while letting stderr go to /dev/null
OUTPUT=$(cd "$WS_D" && bash "$REGRESSION" baseline.json degraded.json --threshold 10 2>/dev/null) || true
RESULT=$(python3 -c "
import json, sys
raw = '''$OUTPUT'''
result = json.loads(raw)
assert result['verdict'] == 'FAIL', f'verdict={result[\"verdict\"]}'
assert len(result['regressions']) == 12, f'regressions={len(result[\"regressions\"])} expected=12'
for r in result['regressions']:
    assert r['delta_pct'] == -37.5, f'{r[\"dimension\"]} delta={r[\"delta_pct\"]}'
print('OK')
" 2>&1)
[[ "$RESULT" == "OK" ]] && tap_ok "Degraded vs baseline: all 12 dimensions flagged as regressed" \
  || tap_fail "Degraded vs baseline: not all dimensions caught" "$RESULT"

# T20: Selective regression — 3 dims regress, 9 improve
WS_D2="$WORK/selective"
init_workspace "$WS_D2"

python3 -c "
import json
dim_ids = ['task_decomposition','parallel_efficiency','context_isolation',
           'token_efficiency','test_coverage_delta','diagram_accuracy',
           'guardrail_compliance','recovery_resilience','learning_retention',
           'pipeline_autonomy','time_to_feature','rework_rate']
bl_dims = {}
for d in dim_ids:
    bl_dims[d] = {'mean': 8.0, 'stddev': 0, 'min': 8.0, 'max': 8.0, 'weight': 1.0, 'weighted_score': 8.0}
bl = {'fixture':'test','k':1,'dimensions':bl_dims,'overall_score':96.0,'overall_max':120.0}
cu_dims = {}
for i, d in enumerate(dim_ids):
    val = 5.0 if i < 3 else 10.0
    cu_dims[d] = {'mean': val, 'stddev': 0, 'min': val, 'max': val, 'weight': 1.0, 'weighted_score': val}
cu = {'fixture':'test','k':1,'dimensions':cu_dims,'overall_score':sum(5.0 if i<3 else 10.0 for i in range(12)),'overall_max':120.0}
with open('$WS_D2/baseline.json','w') as f: json.dump(bl,f,indent=2)
with open('$WS_D2/current.json','w') as f: json.dump(cu,f,indent=2)
"

OUTPUT=$(cd "$WS_D2" && bash "$REGRESSION" baseline.json current.json --threshold 10 2>/dev/null) || true
RESULT=$(python3 -c "
import json
result = json.loads('''$OUTPUT''')
assert result['verdict'] == 'FAIL'
assert len(result['regressions']) == 3, f'regressions={len(result[\"regressions\"])}'
assert len(result['improvements']) == 9, f'improvements={len(result[\"improvements\"])}'
print('OK')
" 2>&1)
[[ "$RESULT" == "OK" ]] && tap_ok "Selective regression: 3 regressed, 9 improved correctly detected" \
  || tap_fail "Selective regression: incorrect detection" "$RESULT"

# ===================================================================
# TEST GROUP 12: Large K — K=10 with all 12 dimensions
# ===================================================================
echo "# --- Large K ---"

# T21: K=10 produces correct scoring across all 12 dimensions
WS_LK="$WORK/largek"
init_workspace "$WS_LK"
create_uniform_fixture "$WS_LK" "large-k" "1, 2, 3, 4, 5, 6, 7, 8, 9, 10"
RDIR=$(run_and_score "$WS_LK" "large-k" 10)
if [[ -n "$RDIR" && -f "$RDIR/summary.json" ]]; then
  RESULT=$(check_summary "$RDIR/summary.json" "
assert s['k'] == 10, f'k={s[\"k\"]}'
expected_mean = 5.5
expected_var = sum((x - 5.5)**2 for x in range(1,11)) / 10
expected_stddev = round(math.sqrt(expected_var), 2)
for dim_id, dim in s['dimensions'].items():
    assert dim['mean'] == expected_mean, f'{dim_id} mean={dim[\"mean\"]} expected={expected_mean}'
    assert dim['stddev'] == expected_stddev, f'{dim_id} stddev={dim[\"stddev\"]} expected={expected_stddev}'
    assert dim['min'] == 1
    assert dim['max'] == 10
assert len(s['dimensions']) == 12
")
  [[ "$RESULT" == "OK" ]] && tap_ok "Large K=10: 12 dimensions, correct mean/stddev/min/max" \
    || tap_fail "Large K=10: scoring validation failed" "$RESULT"
else
  tap_fail "Large K=10: runner/scorer failed"
fi

# T22: K=10 run dirs all exist
if [[ -n "${RDIR:-}" ]]; then
  COUNT=$(ls -d "$RDIR"/run-*/metrics.json 2>/dev/null | wc -l)
  COUNT=$(echo "$COUNT" | tr -d ' ')
  if [[ "$COUNT" -eq 10 ]]; then
    tap_ok "Large K=10: all 10 run dirs with metrics.json present"
  else
    tap_fail "Large K=10: expected 10 run dirs, got $COUNT"
  fi
else
  tap_fail "Large K=10: no results dir"
fi

# ===================================================================
# TEST GROUP 13: Runner Error Cases
# ===================================================================
echo "# --- Runner Error Cases ---"

# T23: Missing fixture => exit 1
WS_ERR="$WORK/err"
init_workspace "$WS_ERR"
(cd "$WS_ERR" && bash "$RUNNER" --fixture nonexistent --k 1 >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 1 ]]; then
  tap_ok "Runner: missing fixture exits with code 1"
else
  tap_fail "Runner: missing fixture should exit 1, got $RC"
fi

# T24: Missing --fixture flag => exit 2
(cd "$WS_ERR" && bash "$RUNNER" --k 1 >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 2 ]]; then
  tap_ok "Runner: missing --fixture flag exits with code 2"
else
  tap_fail "Runner: missing --fixture flag should exit 2, got $RC"
fi

# T25: Scorer with empty directory => exit 1
mkdir -p "$WS_ERR/empty-results"
(cd "$WS_ERR" && bash "$SCORER" empty-results >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 1 ]]; then
  tap_ok "Scorer: empty results dir exits with code 1"
else
  tap_fail "Scorer: empty results dir should exit 1, got $RC"
fi

# T26: Regression with missing file => exit 2
(cd "$WS_ERR" && bash "$REGRESSION" nonexistent.json also-nonexistent.json >/dev/null 2>&1)
RC=$?
if [[ $RC -eq 2 ]]; then
  tap_ok "Regression: missing files exits with code 2"
else
  tap_fail "Regression: missing files should exit 2, got $RC"
fi

# ===================================================================
# TAP plan (emitted at end — valid per TAP spec)
# ===================================================================
echo "1..$TESTS"

# --- Summary ---
echo "# Total: $TESTS tests, $FAILURES failures"
if [[ $FAILURES -eq 0 ]]; then
  echo "# PASS: all DOB stress tests passed"
  exit 0
else
  echo "# FAIL: $FAILURES test(s) failed"
  exit 1
fi
