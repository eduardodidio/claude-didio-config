#!/usr/bin/env bash
# tests/F28-rtk-smoke.sh — tests for RTK smoke check, config helper, and CLI wrapper.
# Hermetic: tmpdir sandbox, mocked binaries, no network.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_REPO="$(cd "$THIS_DIR/.." && pwd)"
SMOKE="$DIDIO_REPO/bin/didio-rtk-smoke.sh"
WRAPPER="$DIDIO_REPO/bin/didio-rtk.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

write_config() {
  local path="$1"
  local rtk_enabled="${2:-false}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{
  "graphify": { "enabled": false },
  "rtk": { "enabled": $rtk_enabled },
  "session_guard": { "enabled": false }
}
JSON
}

mk_rtk_mock() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/rtk" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "rtk 0.2.0-mock"
elif [[ "${1:-}" == "gain" ]]; then
  echo "total savings: 42%"
else
  echo "rtk mock: $*"
fi
EOF
  chmod +x "$dir/rtk"
}

mk_empty_bin() {
  local dir="$1"
  mkdir -p "$dir"
}

# ── T1: Smoke — disabled → exit 0, disabled message ──
(
  prj="$SANDBOX/t1"; write_config "$prj/didio.config.json" "false"
  bin="$SANDBOX/t1-bin"; mk_empty_bin "$bin"

  stderr="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'rtk disabled'; then
    pass "T1: disabled → exit 0"
  else
    fail "T1: expected exit 0 + disabled, got rc=$rc stderr='$stderr'"
  fi
) || FAIL=1

# ── T2: Smoke — enabled + found → exit 0, available ──
(
  prj="$SANDBOX/t2"; write_config "$prj/didio.config.json" "true"
  bin="$SANDBOX/t2-bin"; mk_rtk_mock "$bin"

  stderr="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'rtk available'; then
    pass "T2: enabled + found → exit 0, available"
  else
    fail "T2: expected exit 0 + available, got rc=$rc stderr='$stderr'"
  fi
) || FAIL=1

# ── T3: Smoke — enabled + not found → exit 0, WARN ──
(
  prj="$SANDBOX/t3"; write_config "$prj/didio.config.json" "true"
  bin="$SANDBOX/t3-bin"; mk_empty_bin "$bin"

  stderr="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'WARN'; then
    pass "T3: enabled + not found → exit 0, WARN"
  else
    fail "T3: expected exit 0 + WARN, got rc=$rc stderr='$stderr'"
  fi
) || FAIL=1

# ── T4: Config helper — didio_rtk_enabled ──
(
  prj="$SANDBOX/t4"; write_config "$prj/didio.config.json" "true"

  result="$(
    export PROJECT_ROOT="$prj"
    source "$DIDIO_REPO/bin/didio-config-lib.sh"
    didio_rtk_enabled
  )"

  if [[ "$result" == "true" ]]; then
    pass "T4: didio_rtk_enabled returns true"
  else
    fail "T4: expected true, got '$result'"
  fi
) || FAIL=1

# ── T5: CLI wrapper — disabled → exit 1 ──
(
  prj="$SANDBOX/t5"; write_config "$prj/didio.config.json" "false"
  bin="$SANDBOX/t5-bin"; mk_rtk_mock "$bin"

  stderr="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$WRAPPER" --version 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 1 ]] && echo "$stderr" | grep -q 'disabled'; then
    pass "T5: CLI wrapper disabled → exit 1"
  else
    fail "T5: expected exit 1 + disabled, got rc=$rc stderr='$stderr'"
  fi
) || FAIL=1

# ── T6: CLI wrapper — enabled + found → passthrough ──
(
  prj="$SANDBOX/t6"; write_config "$prj/didio.config.json" "true"
  bin="$SANDBOX/t6-bin"; mk_rtk_mock "$bin"

  output="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$WRAPPER" --version 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'rtk 0.2.0-mock'; then
    pass "T6: CLI wrapper enabled → passthrough to rtk"
  else
    fail "T6: expected exit 0 + mock version, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── Summary ──
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F28-rtk-smoke.sh: FAILED"
  exit 1
fi
echo "----"
echo "F28-rtk-smoke.sh: ALL PASS"
