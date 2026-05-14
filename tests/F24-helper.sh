#!/usr/bin/env bash
# tests/F24-helper.sh — unit tests for didio_second_brain_home and
# didio_second_brain_installed in bin/didio-config-lib.sh.
# Hermetic: tmpdir sandboxes, no real $HOME mutation, no network.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_HOME="$(cd "$THIS_DIR/.." && pwd)"
LIB="$DIDIO_HOME/bin/didio-config-lib.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# Helper: create a fake second-brain dir structure
mk_sb_dir() {
  local dir="$1"
  mkdir -p "$dir/.git" "$dir/patterns/hooks/stop-session-summary"
  touch "$dir/patterns/hooks/stop-session-summary/hook.sh"
}

# Helper: create a fake second-brain dir WITHOUT the hook layout
mk_sb_dir_no_hooks() {
  local dir="$1"
  mkdir -p "$dir/.git"
}

# Helper: create a minimal didio.config.json with second_brain.home set
mk_config() {
  local dir="$1"
  local home_val="$2"
  cat > "$dir/didio.config.json" <<JSON
{
  "second_brain": {
    "enabled": true,
    "fallback_to_local": true,
    "home": "$home_val"
  }
}
JSON
}

# -----------------------------------------------------------------------
# Test 1: Happy path — env var set, .git + hook layout present → installed
# -----------------------------------------------------------------------
(
  sb="$SANDBOX/t1-sb"
  mk_sb_dir "$sb"

  export DIDIO_SECOND_BRAIN_HOME="$sb"
  unset PROJECT_ROOT 2>/dev/null || true
  source "$LIB"

  result_home="$(didio_second_brain_home)"
  result_installed="$(didio_second_brain_installed)"

  if [[ "$result_home" == "$sb" ]]; then
    pass "T1: didio_second_brain_home returns env var path"
  else
    fail "T1: expected '$sb', got '$result_home'"
  fi

  if [[ "$result_installed" == "true" ]]; then
    pass "T1: didio_second_brain_installed returns true"
  else
    fail "T1: expected 'true', got '$result_installed'"
  fi
)

# -----------------------------------------------------------------------
# Test 2: No env var, no config, no heuristic → empty / false
# -----------------------------------------------------------------------
(
  cfg_dir="$SANDBOX/t2-cfg"
  mkdir -p "$cfg_dir"
  mk_config "$cfg_dir" ""

  export PROJECT_ROOT="$cfg_dir"
  unset DIDIO_SECOND_BRAIN_HOME 2>/dev/null || true
  # Override HOME to a sandbox dir that has no heuristic paths
  export HOME="$SANDBOX/t2-home"
  mkdir -p "$HOME"
  source "$LIB"

  result_home="$(didio_second_brain_home)"
  result_installed="$(didio_second_brain_installed)"

  if [[ -z "$result_home" ]]; then
    pass "T2: didio_second_brain_home returns empty string"
  else
    fail "T2: expected empty, got '$result_home'"
  fi

  if [[ "$result_installed" == "false" ]]; then
    pass "T2: didio_second_brain_installed returns false"
  else
    fail "T2: expected 'false', got '$result_installed'"
  fi
)

# -----------------------------------------------------------------------
# Test 3: Env var set but missing .git → home returns empty, installed false
# -----------------------------------------------------------------------
(
  sb="$SANDBOX/t3-no-git"
  mkdir -p "$sb"  # no .git

  export DIDIO_SECOND_BRAIN_HOME="$sb"
  cfg_dir="$SANDBOX/t3-cfg"
  mkdir -p "$cfg_dir"
  mk_config "$cfg_dir" ""
  export PROJECT_ROOT="$cfg_dir"
  export HOME="$SANDBOX/t3-home"
  mkdir -p "$HOME"
  source "$LIB"

  result_home="$(didio_second_brain_home)"
  result_installed="$(didio_second_brain_installed)"

  if [[ -z "$result_home" ]]; then
    pass "T3: env var without .git → didio_second_brain_home returns empty"
  else
    fail "T3: expected empty, got '$result_home'"
  fi

  if [[ "$result_installed" == "false" ]]; then
    pass "T3: env var without .git → didio_second_brain_installed returns false"
  else
    fail "T3: expected 'false', got '$result_installed'"
  fi
)

# -----------------------------------------------------------------------
# Test 4: Config second_brain.home set, env var unset → returns config value
# -----------------------------------------------------------------------
(
  sb="$SANDBOX/t4-sb"
  mk_sb_dir "$sb"

  cfg_dir="$SANDBOX/t4-cfg"
  mkdir -p "$cfg_dir"
  mk_config "$cfg_dir" "$sb"

  unset DIDIO_SECOND_BRAIN_HOME 2>/dev/null || true
  export PROJECT_ROOT="$cfg_dir"
  export HOME="$SANDBOX/t4-home"
  mkdir -p "$HOME"
  source "$LIB"

  result_home="$(didio_second_brain_home)"

  if [[ "$result_home" == "$sb" ]]; then
    pass "T4: config second_brain.home used when env var unset"
  else
    fail "T4: expected '$sb', got '$result_home'"
  fi
)

# -----------------------------------------------------------------------
# Test 5: Both env var and config set → env var wins (precedence test)
# -----------------------------------------------------------------------
(
  sb_env="$SANDBOX/t5-env-sb"
  mk_sb_dir "$sb_env"

  sb_cfg="$SANDBOX/t5-cfg-sb"
  mk_sb_dir "$sb_cfg"

  cfg_dir="$SANDBOX/t5-cfg"
  mkdir -p "$cfg_dir"
  mk_config "$cfg_dir" "$sb_cfg"

  export DIDIO_SECOND_BRAIN_HOME="$sb_env"
  export PROJECT_ROOT="$cfg_dir"
  export HOME="$SANDBOX/t5-home"
  mkdir -p "$HOME"
  source "$LIB"

  result_home="$(didio_second_brain_home)"

  if [[ "$result_home" == "$sb_env" ]]; then
    pass "T5: env var takes precedence over config"
  else
    fail "T5: expected env var '$sb_env', got '$result_home'"
  fi
)

# -----------------------------------------------------------------------
# Test 6: Strict mode (set -u) — unset DIDIO_SECOND_BRAIN_HOME does not die
# -----------------------------------------------------------------------
(
  set -u
  cfg_dir="$SANDBOX/t6-cfg"
  mkdir -p "$cfg_dir"
  mk_config "$cfg_dir" ""

  unset DIDIO_SECOND_BRAIN_HOME 2>/dev/null || true
  export PROJECT_ROOT="$cfg_dir"
  export HOME="$SANDBOX/t6-home"
  mkdir -p "$HOME"
  source "$LIB"

  # This must not throw "unbound variable"
  result_home="$(didio_second_brain_home 2>&1)" && rc=0 || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "T6: set -u strict mode — unset DIDIO_SECOND_BRAIN_HOME does not crash"
  else
    fail "T6: crashed under set -u with rc=$rc output='$result_home'"
  fi
)

# -----------------------------------------------------------------------
# Test 7: Malformed didio.config.json → returns empty string, does not crash
# -----------------------------------------------------------------------
(
  cfg_dir="$SANDBOX/t7-cfg"
  mkdir -p "$cfg_dir"
  echo "{ broken json !!!" > "$cfg_dir/didio.config.json"

  unset DIDIO_SECOND_BRAIN_HOME 2>/dev/null || true
  export PROJECT_ROOT="$cfg_dir"
  export HOME="$SANDBOX/t7-home"
  mkdir -p "$HOME"
  source "$LIB"

  result_home="$(didio_second_brain_home 2>/dev/null)"
  result_installed="$(didio_second_brain_installed 2>/dev/null)"

  if [[ -z "$result_home" ]]; then
    pass "T7: malformed config → didio_second_brain_home returns empty"
  else
    fail "T7: expected empty on malformed config, got '$result_home'"
  fi

  if [[ "$result_installed" == "false" ]]; then
    pass "T7: malformed config → didio_second_brain_installed returns false"
  else
    fail "T7: expected 'false', got '$result_installed'"
  fi
)

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F24-helper.sh: FAILED"
  exit 1
fi
echo "----"
echo "F24-helper.sh: ALL PASS"
