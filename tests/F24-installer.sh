#!/usr/bin/env bash
# tests/F24-installer.sh — integration tests for the second-brain block in install.sh.
# Hermetic: fake HOME + fake DIDIO_HOME; no network; no real ~/.bashrc mutation.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$THIS_DIR/.." && pwd)"
INSTALL_SH="$REPO_ROOT/install.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a minimal fake $DIDIO_HOME that passes install.sh's "local install" check.
# Accepts an optional second argument to control whether to include a working
# helper script (default=yes) or a failing one or none.
# Usage: mk_fake_didio_home <dir> [ok|fail|missing]
mk_fake_didio_home() {
  local dir="$1"
  local helper="${2:-ok}"
  mkdir -p "$dir/bin"
  touch "$dir/bin/didio"
  chmod +x "$dir/bin/didio"
  case "$helper" in
    ok)
      cat > "$dir/bin/didio-install-second-brain.sh" <<'HELPER'
#!/usr/bin/env bash
TARGET="$1"
mkdir -p "$TARGET/.git"
exit 0
HELPER
      chmod +x "$dir/bin/didio-install-second-brain.sh"
      ;;
    fail)
      cat > "$dir/bin/didio-install-second-brain.sh" <<'HELPER'
#!/usr/bin/env bash
echo "simulated clone failure" >&2
exit 1
HELPER
      chmod +x "$dir/bin/didio-install-second-brain.sh"
      ;;
    missing)
      # do not create the helper
      ;;
  esac
}

# Run install.sh in a sandboxed environment.
# All extra KEY=value arguments are forwarded as env vars.
run_install() {
  local fake_home="$1"
  local fake_didio_home="$2"
  local fake_bin="$3"
  shift 3
  env -i \
    HOME="$fake_home" \
    DIDIO_HOME="$fake_didio_home" \
    DIDIO_BIN_DIR="$fake_bin" \
    SHELL="/bin/bash" \
    PATH="$PATH" \
    "$@" \
    bash "$INSTALL_SH" 2>&1
}

# Count how many times a pattern appears in a file (0 if file missing).
count_in_file() {
  local pattern="$1"
  local file="$2"
  [[ -f "$file" ]] || { echo 0; return; }
  grep -c "$pattern" "$file" 2>/dev/null || echo 0
}

# ---------------------------------------------------------------------------
# Test 1 — Happy path: DIDIO_INSTALL_SB=yes → helper clones, rc snippet added
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t1"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" ok

  output="$(run_install "$fake_home" "$fake_didio" "$fake_bin" DIDIO_INSTALL_SB=yes)"

  expected_sb="$fake_home/didio-second-brain-claude"
  rc_file="$fake_home/.bashrc"

  if [[ -d "$expected_sb/.git" ]]; then
    pass "T1: helper created .git dir at default target"
  else
    fail "T1: expected $expected_sb/.git to exist"
  fi

  if [[ -f "$rc_file" ]] && grep -q 'DIDIO_SECOND_BRAIN_HOME' "$rc_file"; then
    pass "T1: managed block written to .bashrc"
  else
    fail "T1: managed block missing from .bashrc"
  fi

  block_count="$(count_in_file '# >>> didio-second-brain-home' "$rc_file")"
  if [[ "$block_count" -eq 1 ]]; then
    pass "T1: exactly one managed block in .bashrc"
  else
    fail "T1: expected 1 managed block, got $block_count"
  fi

  if echo "$output" | grep -q "second-brain MCP"; then
    pass "T1: next-steps banner mentions second-brain"
  else
    fail "T1: next-steps banner missing second-brain line"
  fi
)

# ---------------------------------------------------------------------------
# Test 2 — Skip path: DIDIO_INSTALL_SB=no → no clone, no rc edit, exit 0
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t2"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" ok

  output="$(run_install "$fake_home" "$fake_didio" "$fake_bin" DIDIO_INSTALL_SB=no)"
  rc=$?

  expected_sb="$fake_home/didio-second-brain-claude"
  rc_file="$fake_home/.bashrc"

  if [[ "$rc" -eq 0 ]]; then
    pass "T2: exit 0 when skipping"
  else
    fail "T2: non-zero exit $rc"
  fi

  if [[ ! -d "$expected_sb" ]]; then
    pass "T2: no clone attempted"
  else
    fail "T2: clone directory should not exist"
  fi

  block_count="$(count_in_file '# >>> didio-second-brain-home' "$rc_file")"
  if [[ "$block_count" -eq 0 ]]; then
    pass "T2: no managed block in .bashrc"
  else
    fail "T2: managed block should not be present, found $block_count"
  fi
)

# ---------------------------------------------------------------------------
# Test 3 — Idempotency: pre-existing SB dir, run twice → only one managed block
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t3"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" ok
  # Pre-populate SB dir so detection branch fires
  mkdir -p "$fake_home/didio-second-brain-claude/.git"

  run_install "$fake_home" "$fake_didio" "$fake_bin" DIDIO_INSTALL_SB=yes > /dev/null 2>&1 || true
  run_install "$fake_home" "$fake_didio" "$fake_bin" DIDIO_INSTALL_SB=yes > /dev/null 2>&1 || true

  rc_file="$fake_home/.bashrc"
  block_count="$(count_in_file '# >>> didio-second-brain-home' "$rc_file")"
  if [[ "$block_count" -eq 1 ]]; then
    pass "T3: idempotent — exactly one managed block after two runs"
  else
    fail "T3: expected 1 managed block after 2 runs, got $block_count"
  fi

  export_count="$(count_in_file 'export DIDIO_SECOND_BRAIN_HOME' "$rc_file")"
  if [[ "$export_count" -eq 1 ]]; then
    pass "T3: exactly one export line in .bashrc"
  else
    fail "T3: expected 1 export line, got $export_count"
  fi
)

# ---------------------------------------------------------------------------
# Test 4 — Non-TTY default skip: no TTY + no env var → warning, no clone
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t4"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" ok

  # Redirect stdin from /dev/null to simulate non-TTY
  output="$(env -i \
    HOME="$fake_home" \
    DIDIO_HOME="$fake_didio" \
    DIDIO_BIN_DIR="$fake_bin" \
    SHELL="/bin/bash" \
    PATH="$PATH" \
    bash "$INSTALL_SH" </dev/null 2>&1)"
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    pass "T4: exit 0 on non-TTY with no env var"
  else
    fail "T4: non-zero exit $rc"
  fi

  expected_sb="$fake_home/didio-second-brain-claude"
  if [[ ! -d "$expected_sb" ]]; then
    pass "T4: no clone on non-TTY"
  else
    fail "T4: clone should not happen on non-TTY without env var"
  fi

  if echo "$output" | grep -q "no TTY"; then
    pass "T4: warning about no TTY printed"
  else
    fail "T4: expected 'no TTY' warning in output"
  fi
)

# ---------------------------------------------------------------------------
# Test 5 — Edge: DIDIO_INSTALL_SB=banana non-TTY → falls back to skip
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t5"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" ok

  output="$(env -i \
    HOME="$fake_home" \
    DIDIO_HOME="$fake_didio" \
    DIDIO_BIN_DIR="$fake_bin" \
    SHELL="/bin/bash" \
    DIDIO_INSTALL_SB=banana \
    PATH="$PATH" \
    bash "$INSTALL_SH" </dev/null 2>&1)"
  rc=$?

  expected_sb="$fake_home/didio-second-brain-claude"
  if [[ "$rc" -eq 0 ]]; then
    pass "T5: exit 0 with invalid env var on non-TTY"
  else
    fail "T5: non-zero exit $rc"
  fi

  if [[ ! -d "$expected_sb" ]]; then
    pass "T5: invalid env var non-TTY → no clone (skip fallback)"
  else
    fail "T5: clone should not happen"
  fi
)

# ---------------------------------------------------------------------------
# Test 6 — Error handling: helper exits non-zero → install.sh continues, exit 0
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t6"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" fail

  output="$(run_install "$fake_home" "$fake_didio" "$fake_bin" DIDIO_INSTALL_SB=yes 2>&1)"
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    pass "T6: install.sh exits 0 even when helper fails"
  else
    fail "T6: expected exit 0, got $rc"
  fi

  if echo "$output" | grep -qi "warn\|failed\|later"; then
    pass "T6: warning about clone failure printed"
  else
    fail "T6: expected warning about clone failure in output"
  fi

  rc_file="$fake_home/.bashrc"
  block_count="$(count_in_file '# >>> didio-second-brain-home' "$rc_file")"
  if [[ "$block_count" -eq 0 ]]; then
    pass "T6: no rc snippet when helper failed (SB_HOME empty)"
  else
    fail "T6: rc snippet should not be written when helper fails"
  fi
)

# ---------------------------------------------------------------------------
# Test 7 — Fish shell: no rc edit, manual instruction printed
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t7"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" ok
  # Pre-populate SB dir so we reach the rc-write branch
  mkdir -p "$fake_home/didio-second-brain-claude/.git"

  output="$(env -i \
    HOME="$fake_home" \
    DIDIO_HOME="$fake_didio" \
    DIDIO_BIN_DIR="$fake_bin" \
    SHELL="/usr/bin/fish" \
    PATH="$PATH" \
    bash "$INSTALL_SH" </dev/null 2>&1)"
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    pass "T7: exit 0 with fish shell"
  else
    fail "T7: non-zero exit $rc"
  fi

  if echo "$output" | grep -q "add this manually"; then
    pass "T7: fish shell prints 'add this manually' instruction"
  else
    fail "T7: expected 'add this manually' instruction for fish shell"
  fi

  config_fish="$fake_home/.config/fish/config.fish"
  rc_file_bash="$fake_home/.bashrc"
  rc_file_zsh="$fake_home/.zshrc"
  if [[ ! -f "$config_fish" ]] && ! grep -q 'DIDIO_SECOND_BRAIN_HOME' "$rc_file_bash" 2>/dev/null && \
     ! grep -q 'DIDIO_SECOND_BRAIN_HOME' "$rc_file_zsh" 2>/dev/null; then
    pass "T7: no rc file edited for fish shell"
  else
    fail "T7: rc file should not be edited for fish shell"
  fi
)

# ---------------------------------------------------------------------------
# Test 8 — Boundary: rc file does not exist → touch creates it, snippet appended
# ---------------------------------------------------------------------------
(
  t="$SANDBOX/t8"
  fake_home="$t/home"
  fake_didio="$t/didio"
  fake_bin="$t/bin"
  mkdir -p "$fake_home" "$fake_bin"
  mk_fake_didio_home "$fake_didio" ok

  rc_file="$fake_home/.bashrc"
  # Ensure rc file does NOT exist
  [[ ! -f "$rc_file" ]] || rm "$rc_file"

  run_install "$fake_home" "$fake_didio" "$fake_bin" DIDIO_INSTALL_SB=yes > /dev/null 2>&1 || true

  if [[ -f "$rc_file" ]]; then
    pass "T8: .bashrc created by touch when absent"
  else
    fail "T8: .bashrc should have been created"
  fi

  if grep -q 'export DIDIO_SECOND_BRAIN_HOME' "$rc_file"; then
    pass "T8: snippet appended to newly created .bashrc"
  else
    fail "T8: snippet missing from newly created .bashrc"
  fi
)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F24-installer.sh: FAILED"
  exit 1
fi
echo "----"
echo "F24-installer.sh: ALL PASS"
