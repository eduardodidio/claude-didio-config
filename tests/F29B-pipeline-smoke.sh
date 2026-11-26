#!/usr/bin/env bash
# tests/F29B-pipeline-smoke.sh -- Smoke tests for F29B pipeline automation scripts.
# Validates syntax, config helpers, and signal directory setup.
# Hermetic: tmpdir sandbox, no network, no agent spawning.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_REPO="$(cd "$THIS_DIR/.." && pwd)"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0
TEST_NUM=0

pass() { TEST_NUM=$((TEST_NUM + 1)); PASS_COUNT=$((PASS_COUNT + 1)); echo "ok $TEST_NUM - $*"; }
fail() { TEST_NUM=$((TEST_NUM + 1)); FAIL_COUNT=$((FAIL_COUNT + 1)); echo "not ok $TEST_NUM - $*"; }

# ---------------------------------------------------------------------------
# Helper: write a minimal didio.config.json
# ---------------------------------------------------------------------------
write_config() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/didio.config.json" <<'JSON'
{
  "negotiation": {
    "max_rounds": 3,
    "post_work_review": true
  },
  "pipeline": {
    "autonomous": true,
    "signal_dir": "logs/agents/signals"
  },
  "token_monitor": {
    "enabled": true,
    "check_interval_minutes": 10
  },
  "meta_agents": {
    "handler": { "enabled": false },
    "gatekeeper": { "enabled": false }
  },
  "session_guard": { "enabled": false }
}
JSON
}

# ═══════════════════════════════════════════════════════════════════════
# 1. Syntax checks (bash -n) for all F29B scripts
# ═══════════════════════════════════════════════════════════════════════

SCRIPTS=(
  "bin/didio-run-pipeline.sh"
  "bin/didio-pipeline-status.sh"
  "bin/didio-pipeline-pause.sh"
  "bin/didio-pipeline-resume.sh"
  "bin/didio-negotiation-loop.sh"
  "bin/didio-post-review.sh"
  "bin/didio-token-monitor.sh"
)

for script in "${SCRIPTS[@]}"; do
  script_path="$DIDIO_REPO/$script"
  if [[ ! -f "$script_path" ]]; then
    fail "syntax: $script exists"
    continue
  fi
  if bash -n "$script_path" 2>/dev/null; then
    pass "syntax: $script passes bash -n"
  else
    fail "syntax: $script passes bash -n"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# 2. Config helpers return correct values
# ═══════════════════════════════════════════════════════════════════════

write_config "$SANDBOX/project"
export PROJECT_ROOT="$SANDBOX/project"
export DIDIO_HOME="$DIDIO_REPO"

# Source config lib
# shellcheck disable=SC1091
source "$DIDIO_REPO/bin/didio-config-lib.sh"

# Test negotiation.max_rounds
val="$(didio_negotiation_max_rounds)"
if [[ "$val" == "3" ]]; then
  pass "config: negotiation.max_rounds returns 3"
else
  fail "config: negotiation.max_rounds returns 3 (got: $val)"
fi

# Test post_work_review
val="$(didio_post_work_review_enabled)"
if [[ "$val" == "true" ]]; then
  pass "config: post_work_review returns true"
else
  fail "config: post_work_review returns true (got: $val)"
fi

# Test pipeline.autonomous
val="$(didio_pipeline_autonomous)"
if [[ "$val" == "true" ]]; then
  pass "config: pipeline.autonomous returns true"
else
  fail "config: pipeline.autonomous returns true (got: $val)"
fi

# Test pipeline.signal_dir
val="$(didio_pipeline_signal_dir)"
if [[ "$val" == "logs/agents/signals" ]]; then
  pass "config: pipeline.signal_dir returns logs/agents/signals"
else
  fail "config: pipeline.signal_dir returns logs/agents/signals (got: $val)"
fi

# Test token_monitor.enabled
val="$(didio_token_monitor_enabled)"
if [[ "$val" == "true" ]]; then
  pass "config: token_monitor.enabled returns true"
else
  fail "config: token_monitor.enabled returns true (got: $val)"
fi

# Test token_monitor.check_interval_minutes
val="$(didio_token_monitor_interval)"
if [[ "$val" == "10" ]]; then
  pass "config: token_monitor.check_interval_minutes returns 10"
else
  fail "config: token_monitor.check_interval_minutes returns 10 (got: $val)"
fi

# ═══════════════════════════════════════════════════════════════════════
# 3. Config defaults (no config file)
# ═══════════════════════════════════════════════════════════════════════

export PROJECT_ROOT="$SANDBOX/no-config"
mkdir -p "$SANDBOX/no-config"

val="$(didio_negotiation_max_rounds)"
if [[ "$val" == "3" ]]; then
  pass "config-default: negotiation.max_rounds defaults to 3"
else
  fail "config-default: negotiation.max_rounds defaults to 3 (got: $val)"
fi

val="$(didio_pipeline_signal_dir)"
if [[ "$val" == "logs/agents/signals" ]]; then
  pass "config-default: pipeline.signal_dir defaults to logs/agents/signals"
else
  fail "config-default: pipeline.signal_dir defaults to logs/agents/signals (got: $val)"
fi

# Restore PROJECT_ROOT for remaining tests
export PROJECT_ROOT="$SANDBOX/project"

# ═══════════════════════════════════════════════════════════════════════
# 4. Signal directory creation
# ═══════════════════════════════════════════════════════════════════════

SIG_DIR="$PROJECT_ROOT/$(didio_pipeline_signal_dir)"
mkdir -p "$SIG_DIR"
if [[ -d "$SIG_DIR" ]]; then
  pass "signal-dir: signal directory exists after mkdir"
else
  fail "signal-dir: signal directory exists after mkdir"
fi

# Test signal file creation (simulating pause/resume)
touch "$SIG_DIR/F99.pause"
if [[ -f "$SIG_DIR/F99.pause" ]]; then
  pass "signal-dir: can create pause signal file"
else
  fail "signal-dir: can create pause signal file"
fi

rm -f "$SIG_DIR/F99.pause"
if [[ ! -f "$SIG_DIR/F99.pause" ]]; then
  pass "signal-dir: can remove signal file"
else
  fail "signal-dir: can remove signal file"
fi

# ═══════════════════════════════════════════════════════════════════════
# 5. Scripts are executable
# ═══════════════════════════════════════════════════════════════════════

for script in "${SCRIPTS[@]}"; do
  script_path="$DIDIO_REPO/$script"
  if [[ -x "$script_path" ]]; then
    pass "exec-bit: $script is executable"
  else
    fail "exec-bit: $script is executable"
  fi
done

# ═══════════════════════════════════════════════════════════════════════
# 6. Help flag works for run-pipeline
# ═══════════════════════════════════════════════════════════════════════

help_out="$(bash "$DIDIO_REPO/bin/didio-run-pipeline.sh" --help 2>&1 || true)"
if echo "$help_out" | grep -q "USAGE:" ; then
  pass "help: run-pipeline --help shows USAGE"
else
  fail "help: run-pipeline --help shows USAGE"
fi

if echo "$help_out" | grep -q "EXIT CODES:" ; then
  pass "help: run-pipeline --help shows EXIT CODES"
else
  fail "help: run-pipeline --help shows EXIT CODES"
fi

# ═══════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════

echo ""
echo "1..$TEST_NUM"
echo "# passed: $PASS_COUNT  failed: $FAIL_COUNT"

if [[ $FAIL_COUNT -gt 0 ]]; then
  exit 1
fi
exit 0
