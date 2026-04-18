#!/usr/bin/env bash
# F06-integration-test.sh — end-to-end test for the second-brain integration:
#   - config helpers (didio_second_brain_enabled / didio_second_brain_fallback)
#   - smoke test exit codes (4 combinations of enabled x fallback x mcp-present)
#   - {{USE_SECOND_BRAIN}} sentinel substitution in the spawn flow
#   - migrate-learnings dry-run parses the local files
#
# Usage: bash tests/F06-integration-test.sh
#
# This test does NOT require a real MCP server running. We stub the `claude`
# binary (for the spawn test) and toggle MCP availability via PATH sleight.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN_DIR="$PROJECT_DIR/bin"
LIB="$BIN_DIR/didio-config-lib.sh"

PASS=0
FAIL=0
FAILURES=()

_pass() { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
_fail() { echo "  [FAIL] $1"; FAILURES+=("$1"); FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Helper: write a synthetic didio.config.json in $1 with second_brain values $2 $3.
_make_config() {
  local dir="$1" enabled="$2" fallback="$3"
  cat > "$dir/didio.config.json" <<EOF
{
  "second_brain": {
    "enabled": $enabled,
    "fallback_to_local": $fallback
  }
}
EOF
}

echo ""
echo "=== F06 Integration Tests ==="
echo ""

# ─── 1. Config helpers ─────────────────────────────────────────────────────────
echo "--- 1. Config helpers ---"

# Test matrix: (enabled, fallback) → expected (enabled_out, fallback_out)
for enabled in true false; do
  for fallback in true false; do
    subdir="$TMP/cfg-$enabled-$fallback"
    mkdir -p "$subdir"
    _make_config "$subdir" "$enabled" "$fallback"
    (
      export PROJECT_ROOT="$subdir"
      # shellcheck disable=SC1090
      source "$LIB"
      actual_e="$(didio_second_brain_enabled)"
      actual_f="$(didio_second_brain_fallback)"
      if [[ "$actual_e" == "$enabled" && "$actual_f" == "$fallback" ]]; then
        echo "  [PASS] enabled=$enabled fallback=$fallback read back correctly"
      else
        echo "  [FAIL] enabled=$enabled fallback=$fallback got ($actual_e,$actual_f)"
        exit 1
      fi
    ) && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); FAILURES+=("helpers enabled=$enabled fallback=$fallback"); }
  done
done

# Edge: missing config → helpers return conservative defaults
(
  export PROJECT_ROOT="$TMP/empty"
  mkdir -p "$PROJECT_ROOT"
  # shellcheck disable=SC1090
  source "$LIB"
  e="$(didio_second_brain_enabled)"
  f="$(didio_second_brain_fallback)"
  # No config at all in the search path: find_config returns "" so both
  # helpers short-circuit to their conservative default.
  if [[ "$e" == "false" && "$f" == "true" ]]; then
    echo "  [PASS] missing config → (enabled=false, fallback=true) defaults"
  else
    echo "  [FAIL] missing config defaults: got ($e,$f) expected (false,true)"
    exit 1
  fi
) && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); FAILURES+=("helpers missing-config"); }

# Edge: block absent entirely in an otherwise-valid config
(
  subdir="$TMP/no-block"
  mkdir -p "$subdir"
  echo '{"turbo": false}' > "$subdir/didio.config.json"
  export PROJECT_ROOT="$subdir"
  # shellcheck disable=SC1090
  source "$LIB"
  e="$(didio_second_brain_enabled)"
  f="$(didio_second_brain_fallback)"
  if [[ "$e" == "false" && "$f" == "true" ]]; then
    echo "  [PASS] absent second_brain block → (false, true)"
  else
    echo "  [FAIL] absent block: got ($e,$f)"
    exit 1
  fi
) && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); FAILURES+=("helpers block-absent"); }

# ─── 2. Smoke test exit codes ─────────────────────────────────────────────────
echo ""
echo "--- 2. Smoke test exit codes ---"

SMOKE="$BIN_DIR/didio-second-brain-smoke.sh"

# Tests run the smoke with DIDIO_HOME pointing at the real project so the
# smoke script finds the *new* config-lib (with the second_brain helpers).
# HOME is redirected to an empty dir so ~/.claude/mcp.json doesn't influence
# the MCP-availability heuristic.
_run_smoke() {
  local proj="$1" stubbin="$2"
  local path="/usr/bin:/bin:$(dirname "$(command -v python3)")"
  [[ -n "$stubbin" ]] && path="$stubbin:$path"
  PROJECT_ROOT="$proj" DIDIO_HOME="$PROJECT_DIR" HOME="$proj" PATH="$path" "$SMOKE"
}

# (A) enabled=false → exit 0 regardless of MCP
subdir="$TMP/smoke-disabled"
mkdir -p "$subdir"
_make_config "$subdir" false true
if _run_smoke "$subdir" "" >/dev/null 2>&1; then
  _pass "smoke: enabled=false → exit 0"
else
  _fail "smoke: enabled=false should exit 0"
fi

# (B) enabled=true, stubbed `claude mcp list` with second-brain → exit 0
subdir="$TMP/smoke-online"
mkdir -p "$subdir/stubbin"
_make_config "$subdir" true true
cat > "$subdir/stubbin/claude" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "mcp" && "$2" == "list" ]]; then
  echo "second-brain: /fake/path/mcp-server"
fi
STUB
chmod +x "$subdir/stubbin/claude"
if _run_smoke "$subdir" "$subdir/stubbin" >/dev/null 2>&1; then
  _pass "smoke: enabled=true + MCP online → exit 0"
else
  _fail "smoke: enabled=true + MCP online should exit 0"
fi

# (C) enabled=true, MCP absent, fallback=true → exit 0 (with warning)
subdir="$TMP/smoke-degraded"
mkdir -p "$subdir/stubbin"
_make_config "$subdir" true true
cat > "$subdir/stubbin/claude" <<'STUB'
#!/usr/bin/env bash
true
STUB
chmod +x "$subdir/stubbin/claude"
if _run_smoke "$subdir" "$subdir/stubbin" >/dev/null 2>&1; then
  _pass "smoke: enabled=true + MCP absent + fallback=true → exit 0"
else
  _fail "smoke: degraded-with-fallback should exit 0"
fi

# (D) enabled=true, MCP absent, fallback=false → exit 2
subdir="$TMP/smoke-hard-fail"
mkdir -p "$subdir/stubbin"
_make_config "$subdir" true false
cat > "$subdir/stubbin/claude" <<'STUB'
#!/usr/bin/env bash
true
STUB
chmod +x "$subdir/stubbin/claude"
set +e
_run_smoke "$subdir" "$subdir/stubbin" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" == "2" ]]; then
  _pass "smoke: enabled=true + MCP absent + fallback=false → exit 2"
else
  _fail "smoke: hard-fail should exit 2, got $rc"
fi

# ─── 3. Sentinel substitution ─────────────────────────────────────────────────
echo ""
echo "--- 3. Sentinel substitution ---"

# Simulate the spawn script's substitution step directly (the full claude
# invocation is out of scope — we only need to confirm the sentinel flip).
for enabled in true false; do
  subdir="$TMP/sent-$enabled"
  mkdir -p "$subdir"
  _make_config "$subdir" "$enabled" true
  (
    export PROJECT_ROOT="$subdir"
    # shellcheck disable=SC1090
    source "$LIB"
    tpl="$(cat "$PROJECT_DIR/templates/agents/prompts/architect.md")"
    sb="$(didio_second_brain_enabled)"
    out="${tpl//\{\{USE_SECOND_BRAIN\}\}/$sb}"
    if echo "$out" | grep -q "Memory source for this run: \*\*${enabled}\*\*"; then
      echo "  [PASS] substitution architect.md → **$enabled**"
    else
      echo "  [FAIL] substitution architect.md missed enabled=$enabled"
      exit 1
    fi
  ) && PASS=$((PASS + 1)) || { FAIL=$((FAIL + 1)); FAILURES+=("sentinel arch enabled=$enabled"); }
done

# All 4 prompt templates carry exactly one sentinel
for role in architect developer techlead qa; do
  n="$(grep -c '{{USE_SECOND_BRAIN}}' "$PROJECT_DIR/templates/agents/prompts/${role}.md" || true)"
  if [[ "$n" == "1" ]]; then
    _pass "sentinel count ${role}.md = 1"
  else
    _fail "sentinel count ${role}.md = $n (expected 1)"
  fi
done

# qa.md also carries the memory_add instruction for the retro
if grep -q 'memory_add' "$PROJECT_DIR/templates/agents/prompts/qa.md"; then
  _pass "qa.md mentions memory_add (retro ceremony)"
else
  _fail "qa.md missing memory_add instruction"
fi

# ─── 4. Migrate-learnings dry-run ─────────────────────────────────────────────
echo ""
echo "--- 4. Migrate-learnings dry-run ---"

if command -v "$BIN_DIR/didio-migrate-learnings.sh" >/dev/null 2>&1 || [[ -x "$BIN_DIR/didio-migrate-learnings.sh" ]]; then
  count="$(DIDIO_MIGRATE_DRY=1 PROJECT_ROOT="$PROJECT_DIR" "$BIN_DIR/didio-migrate-learnings.sh" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)"
  if [[ -n "${count:-}" && "$count" -ge 9 ]]; then
    _pass "migrate dry-run: $count entries parsed (≥ 9)"
  else
    _fail "migrate dry-run: parsed ${count:-0} entries (expected ≥ 9)"
  fi
else
  _fail "migrate script missing or not executable"
fi

# Dry-run on empty learnings dir returns 0 entries gracefully
TMP_EMPTY="$TMP/empty-proj"
mkdir -p "$TMP_EMPTY"
set +e
out="$(DIDIO_MIGRATE_DRY=1 PROJECT_ROOT="$TMP_EMPTY" "$BIN_DIR/didio-migrate-learnings.sh" 2>&1)"
rc=$?
set -e
if [[ "$rc" == "0" ]]; then
  _pass "migrate dry-run on empty project → exit 0"
else
  _fail "migrate dry-run on empty project: rc=$rc"
fi

# ─── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  echo ""
  echo "Failures:"
  for f in "${FAILURES[@]}"; do
    echo "  - $f"
  done
  echo ""
  exit 1
fi
echo ""
echo "All tests passed."
