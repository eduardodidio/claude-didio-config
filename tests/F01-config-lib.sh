#!/usr/bin/env bash
# F01-config-lib.sh — unit tests for provider helpers in didio-config-lib.sh:
#   - didio_provider_for_role
#   - didio_provider_bin
#   - didio_provider_model_for_role (alias of didio_model_for_role)
# Usage: bash tests/F01-config-lib.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/with-config" "$TMP/no-config"
cat > "$TMP/with-config/didio.config.json" <<'EOF'
{
  "economy": true,
  "providers": {
    "claude": { "bin": "claude" },
    "codex": { "bin": "codex-cli" }
  },
  "models": {
    "developer": { "provider": "codex", "model": "gpt-5-codex", "fallback": "o4-mini" },
    "techlead": { "model": "sonnet", "fallback": "haiku" }
  },
  "models_economy": {
    "developer": { "provider": "codex", "model": "o4-mini" }
  }
}
EOF

TOTAL_PASS=0
TOTAL_FAIL=0

run_case() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  [PASS] $desc"
    (( TOTAL_PASS++ )) || true
  else
    echo "  [FAIL] $desc (expected '$expected', got '$actual')"
    (( TOTAL_FAIL++ )) || true
  fi
}

source "$BIN_DIR/didio-config-lib.sh"

# ─── With config, economy: true → reads models_economy ───────────────────────
export PROJECT_ROOT="$TMP/with-config"
run_case "provider_for_role developer (economy) -> codex" "codex" "$(didio_provider_for_role developer)"
run_case "provider_bin codex -> codex-cli" "codex-cli" "$(didio_provider_bin codex)"
run_case "provider_model_for_role developer (economy) -> o4-mini" "o4-mini" "$(didio_provider_model_for_role developer)"

# edge case: role with no provider field -> claude
run_case "provider_for_role techlead (no provider) -> claude" "claude" "$(didio_provider_for_role techlead)"

# boundary: unknown provider falls back to its own name
run_case "provider_bin unknownprov -> unknownprov" "unknownprov" "$(didio_provider_bin unknownprov)"

# boundary: role absent from config -> claude
run_case "provider_for_role unknownrole -> claude" "claude" "$(didio_provider_for_role unknownrole)"

# ─── With config, economy: false → reads models ──────────────────────────────
python3 -c "
import json
p = '$TMP/with-config/didio.config.json'
c = json.load(open(p))
c['economy'] = False
json.dump(c, open(p, 'w'))
"
run_case "provider_for_role developer (non-economy) -> codex" "codex" "$(didio_provider_for_role developer)"
run_case "provider_model_for_role developer (non-economy) -> gpt-5-codex" "gpt-5-codex" "$(didio_provider_model_for_role developer)"

# ─── Missing config file — safe defaults, no crash ────────────────────────────
# Override DIDIO_HOME too, so didio_find_config has no fallback to discover.
export PROJECT_ROOT="$TMP/no-config"
export DIDIO_HOME="$TMP/no-config"
run_case "provider_for_role (no config) -> claude" "claude" "$(didio_provider_for_role developer)"
run_case "provider_bin (no config) -> name itself" "claude" "$(didio_provider_bin claude)"
run_case "provider_model_for_role (no config) -> empty" "" "$(didio_provider_model_for_role developer)"

# ─── Existing helpers unchanged ───────────────────────────────────────────────
run_case "didio_model_for_role unchanged (no config) -> empty" "" "$(didio_model_for_role developer)"
run_case "didio_fallback_for_role unchanged (no config) -> empty" "" "$(didio_fallback_for_role developer)"

echo ""
echo "Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"

if (( TOTAL_FAIL > 0 )); then
  exit 1
fi
exit 0
