#!/usr/bin/env bash
# tests/F24-helper-clone.sh — integration tests for bin/didio-install-second-brain.sh
# Hermetic: uses local bare git repos as fixtures; no real network calls.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "$0")" && pwd)"
DIDIO_HOME="$(cd "$THIS_DIR/.." && pwd)"
SCRIPT="$DIDIO_HOME/bin/didio-install-second-brain.sh"

SANDBOX="$(mktemp -d)"
cleanup() { rm -rf "$SANDBOX"; }
trap cleanup EXIT

FAIL=0
pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*"; FAIL=1; }

# -----------------------------------------------------------------------
# Shared fixture: a local bare repo that looks like didio-second-brain-claude
# -----------------------------------------------------------------------
FIXTURE_REPO="$SANDBOX/mock-sb-repo.git"
git init --bare "$FIXTURE_REPO" >/dev/null 2>&1

# Seed the bare repo with a minimal commit so it has a default branch
WORK_CLONE="$SANDBOX/work-seed"
git clone "$FIXTURE_REPO" "$WORK_CLONE" >/dev/null 2>&1
mkdir -p "$WORK_CLONE/patterns/hooks/stop-session-summary"
touch "$WORK_CLONE/patterns/hooks/stop-session-summary/hook.sh"
git -C "$WORK_CLONE" add . >/dev/null 2>&1
git -C "$WORK_CLONE" -c user.email="test@test.com" -c user.name="test" \
  commit -m "init" >/dev/null 2>&1
git -C "$WORK_CLONE" push >/dev/null 2>&1

FIXTURE_URL="file://$FIXTURE_REPO"

# Fixture WITHOUT hook layout
FIXTURE_BARE_NOHOOK="$SANDBOX/mock-no-hook.git"
git init --bare "$FIXTURE_BARE_NOHOOK" >/dev/null 2>&1
WORK_NOHOOK="$SANDBOX/work-nohook"
git clone "$FIXTURE_BARE_NOHOOK" "$WORK_NOHOOK" >/dev/null 2>&1
touch "$WORK_NOHOOK/README.md"
git -C "$WORK_NOHOOK" add . >/dev/null 2>&1
git -C "$WORK_NOHOOK" -c user.email="test@test.com" -c user.name="test" \
  commit -m "init no hooks" >/dev/null 2>&1
git -C "$WORK_NOHOOK" push >/dev/null 2>&1
FIXTURE_NOHOOK_URL="file://$FIXTURE_BARE_NOHOOK"

# -----------------------------------------------------------------------
# Test 1: Happy path (fresh clone)
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t1-target"
  out="$(DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" "$SCRIPT" "$target" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "T1: fresh clone exits 0"
  else
    fail "T1: fresh clone exited $rc"
  fi
  if [[ -d "$target/.git" ]]; then
    pass "T1: .git directory present after clone"
  else
    fail "T1: .git directory missing after clone"
  fi
  if [[ "$out" == "$target" ]]; then
    pass "T1: stdout is the absolute target path"
  else
    fail "T1: expected stdout '$target', got '$out'"
  fi
)

# -----------------------------------------------------------------------
# Test 2: Idempotent (already cloned — no reclone)
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t2-target"
  DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" "$SCRIPT" "$target" >/dev/null 2>&1
  inode_before="$(ls -i "$target/.git/HEAD" | awk '{print $1}')"

  out="$(DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" "$SCRIPT" "$target" 2>/dev/null)"
  rc=$?
  inode_after="$(ls -i "$target/.git/HEAD" | awk '{print $1}')"

  if [[ "$rc" -eq 0 ]]; then
    pass "T2: second run exits 0"
  else
    fail "T2: second run exited $rc"
  fi
  if [[ "$inode_before" == "$inode_after" ]]; then
    pass "T2: inode unchanged (no reclone)"
  else
    fail "T2: inode changed — possible reclone (before=$inode_before after=$inode_after)"
  fi
  if [[ "$out" == "$target" ]]; then
    pass "T2: stdout still returns the path"
  else
    fail "T2: stdout mismatch: '$out'"
  fi
)

# -----------------------------------------------------------------------
# Test 3: Non-git existing dir → exit 2 with clear error
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t3-non-git"
  mkdir -p "$target"
  touch "$target/foo"

  stderr_out="$(DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" "$SCRIPT" "$target" 2>&1 >/dev/null || true)"
  rc=0
  DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" "$SCRIPT" "$target" >/dev/null 2>/dev/null \
    && rc=0 || rc=$?

  if [[ "$rc" -eq 2 ]]; then
    pass "T3: non-git dir exits 2"
  else
    fail "T3: expected exit 2, got $rc"
  fi
  if [[ "$stderr_out" == *"not a git checkout"* ]]; then
    pass "T3: stderr mentions 'not a git checkout'"
  else
    fail "T3: stderr did not mention 'not a git checkout': '$stderr_out'"
  fi
)

# -----------------------------------------------------------------------
# Test 4: Custom URL via env var
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t4-target"
  out="$(DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" "$SCRIPT" "$target" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 && -d "$target/.git" ]]; then
    pass "T4: custom DIDIO_SECOND_BRAIN_REPO_URL clones from fixture"
  else
    fail "T4: custom URL clone failed (rc=$rc)"
  fi
)

# -----------------------------------------------------------------------
# Test 5: Sanity-check warn when hook layout missing
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t5-target"
  stderr_out="$(DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_NOHOOK_URL" "$SCRIPT" "$target" 2>&1 >/dev/null)"
  rc=0
  DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_NOHOOK_URL" "$SCRIPT" "$target" >/dev/null 2>/dev/null \
    && rc=0 || rc=$?

  if [[ "$rc" -eq 0 ]]; then
    pass "T5: missing hook layout still exits 0"
  else
    fail "T5: expected exit 0 on missing hook layout, got $rc"
  fi
  if [[ "$stderr_out" == *"hook layout missing"* || "$stderr_out" == *"upstream may have changed"* ]]; then
    pass "T5: warn printed for missing hook layout"
  else
    fail "T5: expected warn about hook layout, stderr: '$stderr_out'"
  fi
)

# -----------------------------------------------------------------------
# Test 6: Path normalization (relative → absolute in stdout)
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t6-target"
  # Pass a relative path by cd-ing to sandbox
  abs_expected="$target"
  out="$(cd "$SANDBOX" && DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" \
    "$SCRIPT" "t6-target" 2>/dev/null)"
  if [[ "$out" == "$abs_expected" ]]; then
    pass "T6: relative path normalized to absolute in stdout"
  else
    fail "T6: expected '$abs_expected', got '$out'"
  fi
)

# -----------------------------------------------------------------------
# Test 7: git missing → exit 1 with clear error
# Use 'bash SCRIPT' explicitly so the shebang is bypassed when PATH is restricted.
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t7-target"
  stderr_out="$(PATH="/nonexistent-dir" /bin/bash "$SCRIPT" "$target" 2>&1 >/dev/null || true)"
  rc=0
  PATH="/nonexistent-dir" /bin/bash "$SCRIPT" "$target" >/dev/null 2>/dev/null \
    && rc=0 || rc=$?

  if [[ "$rc" -eq 1 ]]; then
    pass "T7: git missing → exit 1"
  else
    fail "T7: expected exit 1 (git missing), got $rc"
  fi
  if [[ "$stderr_out" == *"git is required"* ]]; then
    pass "T7: stderr says 'git is required'"
  else
    fail "T7: unexpected stderr: '$stderr_out'"
  fi
)

# -----------------------------------------------------------------------
# Test 8: --help flag prints usage and exits 0 with no side effects
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t8-target"
  out="$("$SCRIPT" --help 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    pass "T8: --help exits 0"
  else
    fail "T8: --help exited $rc"
  fi
  if [[ "$out" == *"Usage:"* ]]; then
    pass "T8: --help prints Usage:"
  else
    fail "T8: --help output missing 'Usage:': '$out'"
  fi
  if [[ ! -d "$target" ]]; then
    pass "T8: --help has no side effects (target not created)"
  else
    fail "T8: --help created target dir unexpectedly"
  fi
)

# -----------------------------------------------------------------------
# Test 9: didio subcommand routing
# -----------------------------------------------------------------------
(
  target="$SANDBOX/t9-target"
  didio_bin="$DIDIO_HOME/bin/didio"
  out="$(DIDIO_HOME="$DIDIO_HOME" DIDIO_SECOND_BRAIN_REPO_URL="$FIXTURE_URL" \
    "$didio_bin" install-second-brain "$target" 2>/dev/null)"
  rc=$?
  if [[ "$rc" -eq 0 && -d "$target/.git" ]]; then
    pass "T9: didio install-second-brain routes to helper"
  else
    fail "T9: routing failed (rc=$rc, .git exists=$(test -d "$target/.git" && echo y || echo n))"
  fi
  if [[ "$out" == "$target" ]]; then
    pass "T9: stdout is the target path via subcommand route"
  else
    fail "T9: stdout mismatch via subcommand: '$out'"
  fi
)

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
if [[ "$FAIL" -ne 0 ]]; then
  echo "----"
  echo "F24-helper-clone.sh: FAILED"
  exit 1
fi
echo "----"
echo "F24-helper-clone.sh: ALL PASS"
