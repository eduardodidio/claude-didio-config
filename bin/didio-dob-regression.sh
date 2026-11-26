#!/usr/bin/env bash
# didio-dob-regression.sh — Compare DOB baseline vs current, gate on regression
# Usage: didio dob-regression <baseline-summary.json> <current-summary.json> [--threshold <pct>]
set -euo pipefail

# --- help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
USAGE:
  didio dob-regression <baseline-summary.json> <current-summary.json> [--threshold <pct>]

ARGUMENTS:
  baseline-summary.json   Path to the baseline summary.json (from dob-score)
  current-summary.json    Path to the current summary.json (from dob-score)

FLAGS:
  --threshold <pct>       Regression threshold percentage (overrides config, default: 10)
  --help, -h              Show this help and exit

EXIT CODES:
  0  No regression beyond threshold (PASS)
  1  At least one dimension regressed beyond threshold (FAIL)
  2  Invalid input (missing files, bad JSON)

OUTPUT:
  JSON verdict on stdout with regressions and improvements.
HELP
  exit 0
fi

# --- read config threshold ---
CFG_THRESHOLD=$(python3 -c "
import json
try:
    c = json.load(open('didio.config.json'))
    print(c.get('dob',{}).get('regression',{}).get('threshold_pct', 10))
except Exception:
    print(10)
" 2>/dev/null)

# --- parse args ---
BASELINE=""
CURRENT=""
THRESHOLD="$CFG_THRESHOLD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --help|-h)   exec "$0" --help ;;
    *)
      if [[ -z "$BASELINE" ]]; then
        BASELINE="$1"
      elif [[ -z "$CURRENT" ]]; then
        CURRENT="$1"
      else
        echo "[dob-regression] ERROR: unexpected argument: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [[ -z "$BASELINE" || -z "$CURRENT" ]]; then
  echo "[dob-regression] ERROR: both baseline and current summary files required" >&2
  exit 2
fi

for f in "$BASELINE" "$CURRENT"; do
  if [[ ! -f "$f" ]]; then
    echo "[dob-regression] ERROR: file not found: $f" >&2
    exit 2
  fi
done

# --- compare ---
python3 -c "
import json, sys

baseline = json.load(open('$BASELINE'))
current = json.load(open('$CURRENT'))
threshold = float($THRESHOLD)

b_dims = baseline.get('dimensions', {})
c_dims = current.get('dimensions', {})

regressions = []
improvements = []

for dim_id in sorted(set(list(b_dims.keys()) + list(c_dims.keys()))):
    b_mean = b_dims.get(dim_id, {}).get('mean', 0)
    c_mean = c_dims.get(dim_id, {}).get('mean', 0)

    if b_mean == 0:
        # Avoid division by zero; if baseline is 0, any positive is improvement
        delta_pct = 100.0 if c_mean > 0 else 0.0
    else:
        delta_pct = ((c_mean - b_mean) / b_mean) * 100.0

    entry = {
        'dimension': dim_id,
        'baseline': b_mean,
        'current': c_mean,
        'delta_pct': round(delta_pct, 2)
    }

    if delta_pct < -threshold:
        regressions.append(entry)
    elif delta_pct > threshold:
        improvements.append(entry)

verdict = 'FAIL' if regressions else 'PASS'

result = {
    'verdict': verdict,
    'threshold_pct': threshold,
    'regressions': regressions,
    'improvements': improvements,
    'baseline_overall': baseline.get('overall_score', 0),
    'current_overall': current.get('overall_score', 0)
}

print(json.dumps(result, indent=2))

if verdict == 'FAIL':
    print(f'[dob-regression] FAIL: {len(regressions)} dimension(s) regressed beyond {threshold}%', file=sys.stderr)
    sys.exit(1)
else:
    print(f'[dob-regression] PASS: no regressions beyond {threshold}%', file=sys.stderr)
    sys.exit(0)
"
