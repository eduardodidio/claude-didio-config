#!/usr/bin/env bash
# tests/F24-smoke.sh — integration tests for bin/didio-second-brain-smoke.sh
# Tests: AC5 (env-var detection, 4th elif), AC5 regression (3 existing paths),
#        AC8 (rewarded warn text), hard-fail exit code, disabled path.
# Hermetic: tmpdir sandbox, mocked binaries, no network.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_REPO="$(cd "$THIS_DIR/.." && pwd)"
SMOKE="$DIDIO_REPO/bin/didio-second-brain-smoke.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# Create a second-brain dir with full layout (.git + hook)
mk_sb_full() {
  local dir="$1"
  mkdir -p "$dir/.git" "$dir/patterns/hooks/stop-session-summary"
  touch "$dir/patterns/hooks/stop-session-summary/hook.sh"
}

# Create a second-brain dir with .git but NO hook layout
mk_sb_no_hooks() {
  local dir="$1"
  mkdir -p "$dir/.git"
}

# Write a minimal didio.config.json
write_config() {
  local path="$1"
  local enabled="${2:-true}"
  local fallback="${3:-true}"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{
  "second_brain": {
    "enabled": $enabled,
    "fallback_to_local": $fallback
  }
}
JSON
}

# Mock claude that prints "second-brain ✓" for `mcp list`
mk_claude_with_sb() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "mcp" && "${2:-}" == "list" ]]; then
  echo "second-brain ✓"
fi
EOF
  chmod +x "$dir/claude"
}

# Mock claude that returns empty for `mcp list` (MCP not registered)
mk_claude_empty() {
  local dir="$1"
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\n' > "$dir/claude"
  chmod +x "$dir/claude"
}

# -----------------------------------------------------------------------
# T1: AC5 — $DIDIO_SECOND_BRAIN_HOME with full layout triggers 4th elif
# claude is present but returns no second-brain, so only the new path fires.
# -----------------------------------------------------------------------
(
  sb="$SANDBOX/t1-sb"; mk_sb_full "$sb"
  prj="$SANDBOX/t1-prj"; write_config "$prj/didio.config.json"
  home="$SANDBOX/t1-home"; mkdir -p "$home"
  bin="$SANDBOX/t1-bin"; mk_claude_empty "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      DIDIO_SECOND_BRAIN_HOME="$sb" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'second-brain available'; then
    pass "T1: env var detection (4th elif) → exit 0, second-brain available"
  else
    fail "T1: expected exit 0 + second-brain available, got rc=$rc stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# T2: AC5 regression — claude mcp list detection (1st if) still works
# -----------------------------------------------------------------------
(
  prj="$SANDBOX/t2-prj"; write_config "$prj/didio.config.json"
  home="$SANDBOX/t2-home"; mkdir -p "$home"
  bin="$SANDBOX/t2-bin"; mk_claude_with_sb "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'second-brain available'; then
    pass "T2: claude mcp list regression → exit 0, second-brain available"
  else
    fail "T2: expected exit 0 + second-brain available, got rc=$rc stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# T3: AC5 regression — ~/.claude/mcp.json detection (2nd elif) still works
# -----------------------------------------------------------------------
(
  prj="$SANDBOX/t3-prj"; write_config "$prj/didio.config.json"
  home="$SANDBOX/t3-home"
  mkdir -p "$home/.claude"
  echo '{"mcpServers":{"second-brain":{}}}' > "$home/.claude/mcp.json"
  bin="$SANDBOX/t3-bin"; mk_claude_empty "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'second-brain available'; then
    pass "T3: ~/.claude/mcp.json regression → exit 0, second-brain available"
  else
    fail "T3: expected exit 0 + second-brain available, got rc=$rc stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# T4: AC5 regression — project .claude/mcp.json detection (3rd elif) still works
# -----------------------------------------------------------------------
(
  prj="$SANDBOX/t4-prj"; write_config "$prj/didio.config.json"
  mkdir -p "$prj/.claude"
  echo '{"mcpServers":{"second-brain":{}}}' > "$prj/.claude/mcp.json"
  home="$SANDBOX/t4-home"; mkdir -p "$home"
  bin="$SANDBOX/t4-bin"; mk_claude_empty "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'second-brain available'; then
    pass "T4: project .claude/mcp.json regression → exit 0, second-brain available"
  else
    fail "T4: expected exit 0 + second-brain available, got rc=$rc stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# T5: Disabled — second_brain.enabled=false → exit 0, disabled message (unchanged)
# -----------------------------------------------------------------------
(
  prj="$SANDBOX/t5-prj"; write_config "$prj/didio.config.json" "false" "true"
  home="$SANDBOX/t5-home"; mkdir -p "$home"
  bin="$SANDBOX/t5-bin"; mk_claude_empty "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'second-brain disabled'; then
    pass "T5: disabled → exit 0, second-brain disabled (opt-out)"
  else
    fail "T5: expected exit 0 + disabled message, got rc=$rc stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# T6: AC8 — WARN path: nothing detected, fallback_to_local=true
# Warn block must contain new install line, github link, and silence hint.
# -----------------------------------------------------------------------
(
  prj="$SANDBOX/t6-prj"; write_config "$prj/didio.config.json" "true" "true"
  home="$SANDBOX/t6-home"; mkdir -p "$home"
  bin="$SANDBOX/t6-bin"; mk_claude_empty "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  warn_ok=true
  echo "$stderr" | grep -q 'didio install-second-brain'                                   || warn_ok=false
  echo "$stderr" | grep -q 'https://github.com/eduardodidio/didio-second-brain-claude'    || warn_ok=false
  echo "$stderr" | grep -q '"second_brain.enabled": false'                                 || warn_ok=false

  if [[ "$rc" -eq 0 && "$warn_ok" == "true" ]]; then
    pass "T6: WARN path → exit 0, warn contains install cmd + github link + silence hint"
  else
    fail "T6: got rc=$rc warn_ok=$warn_ok stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# T7: Hard fail — nothing detected, fallback_to_local=false → exit 2, ERROR msg
# -----------------------------------------------------------------------
(
  prj="$SANDBOX/t7-prj"; write_config "$prj/didio.config.json" "true" "false"
  home="$SANDBOX/t7-home"; mkdir -p "$home"
  bin="$SANDBOX/t7-bin"; mk_claude_empty "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 2 ]] && echo "$stderr" | grep -q 'ERROR'; then
    pass "T7: hard fail → exit 2, ERROR message unchanged"
  else
    fail "T7: expected exit 2 + ERROR message, got rc=$rc stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# T8: Edge — $DIDIO_SECOND_BRAIN_HOME has .git but no hook layout
# didio_second_brain_installed returns false → falls through to WARN path.
# -----------------------------------------------------------------------
(
  sb="$SANDBOX/t8-sb"; mk_sb_no_hooks "$sb"
  prj="$SANDBOX/t8-prj"; write_config "$prj/didio.config.json" "true" "true"
  home="$SANDBOX/t8-home"; mkdir -p "$home"
  bin="$SANDBOX/t8-bin"; mk_claude_empty "$bin"

  stderr="$(
    env -u DIDIO_SECOND_BRAIN_HOME \
      PROJECT_ROOT="$prj" \
      DIDIO_HOME="$DIDIO_REPO" \
      DIDIO_SECOND_BRAIN_HOME="$sb" \
      HOME="$home" \
      PATH="$bin:$PATH" \
      bash "$SMOKE" 2>&1
  )" && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]] && echo "$stderr" | grep -q 'WARN'; then
    pass "T8: env var with .git but no hooks → falls through to WARN (not treated as installed)"
  else
    fail "T8: expected exit 0 + WARN, got rc=$rc stderr='$stderr'"
    exit 1
  fi
) || FAIL=1

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F24-smoke.sh: FAILED"
  exit 1
fi
echo "----"
echo "F24-smoke.sh: ALL PASS"
