#!/usr/bin/env bash
# didio-dob-runner.sh — Run DOB benchmark K times against a fixture
# Usage: didio dob-run --fixture <name> [--k <N>]
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

# --- help ---
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
USAGE:
  didio dob-run --fixture <name> [--k <N>]

FLAGS:
  --fixture <name>   Name of the fixture file (without .json extension)
                     Looked up in dob.fixtures_dir (default: tests/dob-fixtures)
  --k <N>            Number of runs (overrides dob.k from config, default: 3)
  --help, -h         Show this help and exit

OUTPUT:
  Creates <results_dir>/<fixture>/<timestamp>/run-<N>/metrics.json for each run.
  Exit 0 on success, exit 1 on missing fixture.
HELP
  exit 0
fi

# --- read config ---
read_cfg() {
  python3 -c "
import json, sys
try:
    c = json.load(open('didio.config.json'))
    keys = '$1'.split('.')
    v = c
    for k in keys:
        v = v[k]
    print(v)
except Exception:
    print('$2')
" 2>/dev/null
}

K=$(read_cfg "dob.k" "3")
FIXTURES_DIR=$(read_cfg "dob.fixtures_dir" "tests/dob-fixtures")
RESULTS_DIR=$(read_cfg "dob.results_dir" "logs/dob-results")
DIMENSIONS_SCHEMA=$(read_cfg "dob.dimensions_schema" "docs/dob-dimensions.json")

# --- parse args ---
FIXTURE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fixture) FIXTURE="$2"; shift 2 ;;
    --k)       K="$2"; shift 2 ;;
    *)         echo "[dob-runner] Unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$FIXTURE" ]]; then
  echo "[dob-runner] ERROR: --fixture is required" >&2
  exit 2
fi

FIXTURE_FILE="$FIXTURES_DIR/${FIXTURE}.json"
if [[ ! -f "$FIXTURE_FILE" ]]; then
  echo "[dob-runner] ERROR: fixture not found: $FIXTURE_FILE" >&2
  exit 1
fi

# --- validate dimensions schema ---
if [[ ! -f "$DIMENSIONS_SCHEMA" ]]; then
  echo "[dob-runner] WARNING: dimensions schema not found: $DIMENSIONS_SCHEMA" >&2
fi

# --- create results directory ---
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUN_DIR="$RESULTS_DIR/$FIXTURE/$TIMESTAMP"
mkdir -p "$RUN_DIR"

echo "[dob-runner] fixture=$FIXTURE k=$K results=$RUN_DIR"

# --- execute K runs ---
for ((i=1; i<=K; i++)); do
  RUN_SUBDIR="$RUN_DIR/run-$i"
  mkdir -p "$RUN_SUBDIR"

  # In V0 (offline/synthetic mode), read metric values from the fixture file.
  # Each dimension has a "values" array; pick the i-th value (wrapping if needed).
  python3 -c "
import json, sys, os

fixture = json.load(open('$FIXTURE_FILE'))
metrics_data = fixture.get('metrics', {})
run_index = $i - 1  # 0-based

# Load dimension IDs from schema if available
dim_ids = []
schema_path = '$DIMENSIONS_SCHEMA'
if os.path.exists(schema_path):
    schema = json.load(open(schema_path))
    dim_ids = [d['id'] for d in schema.get('dimensions', [])]

# Build metrics for this run
metrics = {}
for dim_id in (dim_ids if dim_ids else metrics_data.keys()):
    dim_data = metrics_data.get(dim_id, {})
    values = dim_data.get('values', [5])  # default to 5 if missing
    value = values[run_index % len(values)]
    metrics[dim_id] = {
        'value': value,
        'source': 'synthetic'
    }

result = {
    'fixture': '$FIXTURE',
    'run': $i,
    'k': $K,
    'timestamp': '$TIMESTAMP',
    'metrics': metrics
}

out_path = '$RUN_SUBDIR/metrics.json'
with open(out_path, 'w') as f:
    json.dump(result, f, indent=2)
print(f'[dob-runner] run {$i}/{$K} -> {out_path}')
"
done

echo "[dob-runner] done: $K runs written to $RUN_DIR"
