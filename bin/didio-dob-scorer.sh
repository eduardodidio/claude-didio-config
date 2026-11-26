#!/usr/bin/env bash
# didio-dob-scorer.sh — Aggregate DOB benchmark results into a scored summary
# Usage: didio dob-score <results-dir>
set -euo pipefail

# --- help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
USAGE:
  didio dob-score <results-dir>

ARGUMENTS:
  results-dir    Path to a benchmark run directory containing run-*/metrics.json

OUTPUT:
  Writes <results-dir>/summary.json with mean, stddev, min, max per dimension
  and an overall weighted score.
  Exit 0 on success, exit 1 on no metrics found.
HELP
  exit 0
fi

RESULTS_DIR="${1:-}"
if [[ -z "$RESULTS_DIR" ]]; then
  echo "[dob-scorer] ERROR: results-dir argument required" >&2
  exit 2
fi

if [[ ! -d "$RESULTS_DIR" ]]; then
  echo "[dob-scorer] ERROR: directory not found: $RESULTS_DIR" >&2
  exit 1
fi

# --- read dimensions schema for weights ---
DIMENSIONS_SCHEMA=$(python3 -c "
import json
try:
    c = json.load(open('didio.config.json'))
    print(c.get('dob',{}).get('dimensions_schema','docs/dob-dimensions.json'))
except Exception:
    print('docs/dob-dimensions.json')
" 2>/dev/null)

# --- score ---
python3 -c "
import json, os, sys, math, glob

results_dir = '$RESULTS_DIR'
schema_path = '$DIMENSIONS_SCHEMA'

# Load dimension weights
weights = {}
if os.path.exists(schema_path):
    schema = json.load(open(schema_path))
    for d in schema.get('dimensions', []):
        weights[d['id']] = d.get('weight', 1.0)

# Collect all run metrics
run_files = sorted(glob.glob(os.path.join(results_dir, 'run-*/metrics.json')))
if not run_files:
    print('[dob-scorer] ERROR: no run-*/metrics.json found in', results_dir, file=sys.stderr)
    sys.exit(1)

k = len(run_files)
all_metrics = []
fixture_name = ''
for rf in run_files:
    data = json.load(open(rf))
    all_metrics.append(data['metrics'])
    if not fixture_name:
        fixture_name = data.get('fixture', 'unknown')

# Aggregate per dimension
dim_ids = set()
for m in all_metrics:
    dim_ids.update(m.keys())

dimensions = {}
overall_score = 0.0
overall_max = 0.0

for dim_id in sorted(dim_ids):
    values = []
    for m in all_metrics:
        if dim_id in m:
            values.append(m[dim_id]['value'])
    if not values:
        continue
    n = len(values)
    mean = sum(values) / n
    variance = sum((v - mean) ** 2 for v in values) / n if n > 1 else 0.0
    stddev = math.sqrt(variance)
    weight = weights.get(dim_id, 1.0)
    weighted = mean * weight

    dimensions[dim_id] = {
        'mean': round(mean, 2),
        'stddev': round(stddev, 2),
        'min': min(values),
        'max': max(values),
        'weight': weight,
        'weighted_score': round(weighted, 2)
    }
    overall_score += weighted
    overall_max += 10.0 * weight

summary = {
    'fixture': fixture_name,
    'k': k,
    'dimensions': dimensions,
    'overall_score': round(overall_score, 2),
    'overall_max': round(overall_max, 2)
}

out_path = os.path.join(results_dir, 'summary.json')
with open(out_path, 'w') as f:
    json.dump(summary, f, indent=2)
print(f'[dob-scorer] summary written to {out_path}')
print(f'[dob-scorer] overall: {summary[\"overall_score\"]}/{summary[\"overall_max\"]}')
"
