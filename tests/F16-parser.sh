#!/usr/bin/env bash
# tests/F16-parser.sh — verify meeting-parser produces a schema-valid
# manifest from the fixture meeting minutes.
#
# Exit 0 on success; 0 with SKIP message if claude CLI unavailable;
# 1 on failure.
#
# Slow: ~30-60s (LLM call). Set F16_SKIP_PARSER=1 to bypass.

set -euo pipefail

[[ "${F16_SKIP_PARSER:-}" == "1" ]] && {
  echo "[T08] SKIP (F16_SKIP_PARSER=1)"
  exit 0
}

if ! command -v claude >/dev/null 2>&1; then
  echo "[T08] SKIP — claude CLI not available"
  exit 0
fi

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "[T08] SKIP — ANTHROPIC_API_KEY not set"
  exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURE="$PROJECT_ROOT/tests/fixtures/F16-meeting-sample.md"
SCHEMA="$PROJECT_ROOT/tasks/features/F16-meeting-to-poc/manifest.schema.json"
PIPELINE="$PROJECT_ROOT/bin/didio-poc-from-minutes.sh"
SCRATCH="$(mktemp -d -t F16-T08-XXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

[[ -f "$FIXTURE" ]]   || { echo "[T08] FIX missing: $FIXTURE" >&2; exit 1; }
[[ -f "$SCHEMA"  ]]   || { echo "[T08] SCHEMA missing: $SCHEMA" >&2; exit 1; }
[[ -x "$PIPELINE" ]]  || { echo "[T08] PIPELINE missing/not-x: $PIPELINE" >&2; exit 1; }

echo "[T08] running parser against fixture..."
(cd "$PROJECT_ROOT" && "$PIPELINE" "$FIXTURE" --dest "$SCRATCH/poc" --no-smoke --stop-after parse)

MANIFEST="$SCRATCH/poc/_pipeline/manifest.json"
[[ -f "$MANIFEST" ]] || { echo "[T08] FAIL: manifest not produced at $MANIFEST" >&2; exit 1; }

echo "[T08] validating manifest against schema..."
python3 - <<PY
import json, jsonschema, sys
m = json.load(open("$MANIFEST"))
s = json.load(open("$SCHEMA"))
jsonschema.validate(m, s)
assert len(m["screens"])  >= 1, "no screens"
assert len(m["entities"]) >= 1, "no entities"
# cross-ref check
ents = {e["name"] for e in m["entities"]}
for sc in m["screens"]:
    ds = sc.get("data_shape")
    assert ds is None or ds in ents, f"unknown data_shape: {ds}"
print(f"[T08] PASS — {len(m['screens'])} screens, {len(m['entities'])} entities")
PY

# Save the produced manifest as a reusable fixture for T06/T09 smokes.
cp "$MANIFEST" "$PROJECT_ROOT/tests/fixtures/F16-manifest-sample.json"
echo "[T08] saved $PROJECT_ROOT/tests/fixtures/F16-manifest-sample.json"

echo "[T08] OK"
