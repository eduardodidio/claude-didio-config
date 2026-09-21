#!/usr/bin/env bash
# tests/F28-graphify-smoke.sh — tests for Graphify smoke check, config helpers,
# CLI wrapper, and nudge hook.
# Hermetic: tmpdir sandbox, mocked binaries, no network.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_REPO="$(cd "$THIS_DIR/.." && pwd)"
SMOKE="$DIDIO_REPO/bin/didio-graphify-smoke.sh"
WRAPPER="$DIDIO_REPO/bin/didio-graphify.sh"
HOOK="$DIDIO_REPO/bin/hooks/didio-pre-tool.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

write_config() {
  local path="$1"
  local gf_enabled="${2:-false}"
  local query="${3:-true}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{
  "graphify": {
    "enabled": $gf_enabled,
    "auto_index": false,
    "output_dir": "graphify-out",
    "query_before_read": $query
  },
  "rtk": { "enabled": false },
  "session_guard": { "enabled": false }
}
JSON
}

mk_graphify_mock() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/graphify" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "graphify 0.1.0-mock"
elif [[ "${1:-}" == "query" ]]; then
  echo "mock query result for $2"
else
  echo "graphify mock: $*"
fi
EOF
  chmod +x "$dir/graphify"
}

mk_empty_bin() {
  local dir="$1"
  mkdir -p "$dir"
  # Provide a claude stub so the hook doesn't error on `command -v claude`
  cat > "$dir/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$dir/claude"
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

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'graphify disabled'; then
    pass "T1: disabled → exit 0"
  else
    fail "T1: expected exit 0 + disabled, got rc=$rc stderr='$stderr'"
  fi
) || FAIL=1

# ── T2: Smoke — enabled + found → exit 0, available ──
(
  prj="$SANDBOX/t2"; write_config "$prj/didio.config.json" "true"
  bin="$SANDBOX/t2-bin"; mk_graphify_mock "$bin"; mk_empty_bin "$bin"

  stderr="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'graphify available'; then
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

# ── T4: Config helpers — didio_graphify_enabled reads config ──
(
  prj="$SANDBOX/t4"; write_config "$prj/didio.config.json" "true"

  result="$(
    export PROJECT_ROOT="$prj"
    source "$DIDIO_REPO/bin/didio-config-lib.sh"
    didio_graphify_enabled
  )"

  if [[ "$result" == "true" ]]; then
    pass "T4: didio_graphify_enabled returns true"
  else
    fail "T4: expected true, got '$result'"
  fi
) || FAIL=1

# ── T5: Config helpers — didio_graphify_output_dir default ──
(
  prj="$SANDBOX/t5"; write_config "$prj/didio.config.json" "false"

  result="$(
    export PROJECT_ROOT="$prj"
    source "$DIDIO_REPO/bin/didio-config-lib.sh"
    didio_graphify_output_dir
  )"

  if [[ "$result" == "graphify-out" ]]; then
    pass "T5: didio_graphify_output_dir returns graphify-out"
  else
    fail "T5: expected graphify-out, got '$result'"
  fi
) || FAIL=1

# ── T6: CLI wrapper — disabled → exit 1 ──
(
  prj="$SANDBOX/t6"; write_config "$prj/didio.config.json" "false"
  bin="$SANDBOX/t6-bin"; mk_graphify_mock "$bin"

  stderr="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$WRAPPER" --version 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 1 ]] && echo "$stderr" | grep -q 'disabled'; then
    pass "T6: CLI wrapper disabled → exit 1"
  else
    fail "T6: expected exit 1 + disabled, got rc=$rc stderr='$stderr'"
  fi
) || FAIL=1

# ── T7: CLI wrapper — enabled + found → passthrough ──
(
  prj="$SANDBOX/t7"; write_config "$prj/didio.config.json" "true"
  bin="$SANDBOX/t7-bin"; mk_graphify_mock "$bin"

  output="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    PATH="$bin:$PATH" \
    bash "$WRAPPER" --version 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'graphify 0.1.0-mock'; then
    pass "T7: CLI wrapper enabled → passthrough to graphify"
  else
    fail "T7: expected exit 0 + mock version, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── T8: Nudge hook — emits systemMessage for .ts file ──
(
  prj="$SANDBOX/t8"; write_config "$prj/didio.config.json" "true" "true"
  bin="$SANDBOX/t8-bin"; mk_graphify_mock "$bin"; mk_empty_bin "$bin"

  HOOK_INPUT='{"tool_name":"Read","file_path":"/app/src/index.ts"}'

  output="$(
    echo "$HOOK_INPUT" | \
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    DIDIO_PROJECT_ROOT="$prj" \
    PATH="$bin:$PATH" \
    bash "$HOOK" 2>/dev/null
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'Graphify is available'; then
    pass "T8: nudge hook emits systemMessage for .ts file"
  else
    fail "T8: expected exit 0 + nudge message, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── T9: Nudge hook — no nudge for .md file ──
(
  prj="$SANDBOX/t9"; write_config "$prj/didio.config.json" "true" "true"
  bin="$SANDBOX/t9-bin"; mk_graphify_mock "$bin"; mk_empty_bin "$bin"

  HOOK_INPUT='{"tool_name":"Read","file_path":"/app/docs/README.md"}'

  output="$(
    echo "$HOOK_INPUT" | \
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    DIDIO_PROJECT_ROOT="$prj" \
    PATH="$bin:$PATH" \
    bash "$HOOK" 2>/dev/null
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && ! echo "$output" | grep -q 'Graphify'; then
    pass "T9: no nudge for .md file"
  else
    fail "T9: expected exit 0 + no nudge, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── T10: Nudge throttle — verify nudge file is created after first call ──
# The throttle uses /tmp/didio-graphify-nudged-$$ per PID. In real usage,
# repeated hook calls within the same Claude session share $$ and throttle
# correctly. Here we verify the mechanism by checking the temp file exists.
(
  prj="$SANDBOX/t10"; write_config "$prj/didio.config.json" "true" "true"
  bin="$SANDBOX/t10-bin"; mk_graphify_mock "$bin"; mk_empty_bin "$bin"

  HOOK_INPUT='{"tool_name":"Read","file_path":"/app/src/main.py"}'

  # Capture the PID of the hook process and check the nudge dir
  cat > "$SANDBOX/t10-check.sh" <<'CHECKER'
#!/usr/bin/env bash
set -uo pipefail
HOOK="$1"
echo '{"tool_name":"Read","file_path":"/app/src/main.py"}' | bash "$HOOK" >/dev/null 2>/dev/null || true
# Find the most recently created nudge dir
nudge_dir=$(ls -td /tmp/didio-graphify-nudged-* 2>/dev/null | head -1)
if [[ -n "$nudge_dir" ]] && ls "$nudge_dir" | grep -q 'main.py'; then
  echo "THROTTLE_FILE_EXISTS"
fi
CHECKER
  chmod +x "$SANDBOX/t10-check.sh"

  output="$(
    PROJECT_ROOT="$prj" DIDIO_HOME="$DIDIO_REPO" \
    DIDIO_PROJECT_ROOT="$prj" \
    PATH="$bin:$PATH" \
    bash "$SANDBOX/t10-check.sh" "$HOOK"
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$output" | grep -q 'THROTTLE_FILE_EXISTS'; then
    pass "T10: throttle file created after nudge"
  else
    fail "T10: throttle file not found after nudge, got rc=$rc output='$output'"
  fi
) || FAIL=1

# ── Summary ──
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F28-graphify-smoke.sh: FAILED"
  exit 1
fi
echo "----"
echo "F28-graphify-smoke.sh: ALL PASS"
