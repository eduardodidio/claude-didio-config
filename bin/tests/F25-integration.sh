#!/usr/bin/env bash
# F25 integration test — placeholder-safe sync regression guard
# Run: bash bin/tests/F25-integration.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_PH="$REPO_ROOT/tests/F25-fixtures/placeholder-settings.json"
FIXTURE_CLEAN="$REPO_ROOT/tests/F25-fixtures/clean-project-stub/.claude/settings.json"
SYNC_SCRIPT="$REPO_ROOT/bin/didio-sync-project.sh"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# Setup: temp DIDIO_HOME with placeholder-settings as template
# ---------------------------------------------------------------------------
TMPDIR_HOME="$(mktemp -d)"
TMPDIR_PROJ="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_HOME" "$TMPDIR_PROJ"' EXIT

mkdir -p "$TMPDIR_HOME/templates/.claude"
cp "$FIXTURE_PH" "$TMPDIR_HOME/templates/.claude/settings.json"

# Set up target project as a git repo with a clean settings.json
mkdir -p "$TMPDIR_PROJ/.claude"
cp "$FIXTURE_CLEAN" "$TMPDIR_PROJ/.claude/settings.json"
git -C "$TMPDIR_PROJ" init -q
git -C "$TMPDIR_PROJ" commit --allow-empty -m "init" -q

# ---------------------------------------------------------------------------
# Test 1: --dry-run with placeholder-settings source
#   Expect: skipped_ph=2 (two {{...}} hooks), 0 hooks added to target
# ---------------------------------------------------------------------------
OUTPUT=$(DIDIO_HOME="$TMPDIR_HOME" bash "$SYNC_SCRIPT" --dry-run "$TMPDIR_PROJ" 2>&1 || true)

if echo "$OUTPUT" | grep -qE "skipped_ph=[1-9]|[1-9] hook.*placeholder|placeholder.*skipped"; then
  pass "dry-run reports skipped placeholder hooks"
else
  fail "dry-run did not report skipped placeholder hooks. Output: $OUTPUT"
fi

# Target settings.json must not contain any {{ after dry-run
if grep -qF '{{' "$TMPDIR_PROJ/.claude/settings.json" 2>/dev/null; then
  fail "target settings.json contains '{{' — placeholder leaked"
else
  pass "target settings.json has no '{{' after dry-run"
fi

# ---------------------------------------------------------------------------
# Test 2: real merge with placeholder-settings source (no dry-run)
#   Expect: valid hooks (without {{) are added, {{ hooks skipped
# ---------------------------------------------------------------------------
TMPDIR_PROJ2="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_HOME" "$TMPDIR_PROJ" "$TMPDIR_PROJ2"' EXIT

mkdir -p "$TMPDIR_PROJ2/.claude"
cp "$FIXTURE_CLEAN" "$TMPDIR_PROJ2/.claude/settings.json"
git -C "$TMPDIR_PROJ2" init -q
git -C "$TMPDIR_PROJ2" commit --allow-empty -m "init" -q

OUTPUT2=$(DIDIO_HOME="$TMPDIR_HOME" bash "$SYNC_SCRIPT" "$TMPDIR_PROJ2" 2>&1 || true)

# Target must not have {{ hooks
if grep -qF '{{' "$TMPDIR_PROJ2/.claude/settings.json" 2>/dev/null; then
  fail "real merge: target settings.json contains '{{' — placeholder leaked"
else
  pass "real merge: target settings.json has no '{{'"
fi

# Target must have the valid hook that has no {{
if grep -qF '/usr/local/bin/valid-hook.sh' "$TMPDIR_PROJ2/.claude/settings.json" 2>/dev/null; then
  pass "real merge: valid hook (no placeholder) was added"
else
  fail "real merge: valid hook missing from target. Contents: $(cat "$TMPDIR_PROJ2/.claude/settings.json")"
fi

# Output must report skipped_ph or warn about placeholders
if echo "$OUTPUT2" | grep -qE "skipped_ph=[1-9]|[1-9] hook.*placeholder|placeholder.*skipped"; then
  pass "real merge summary reports skipped placeholder hooks"
else
  fail "real merge summary did not report skipped hooks. Output: $OUTPUT2"
fi

# Target JSON must be valid
if python3 -m json.tool "$TMPDIR_PROJ2/.claude/settings.json" >/dev/null 2>&1; then
  pass "real merge: target settings.json is valid JSON"
else
  fail "real merge: target settings.json is not valid JSON"
fi

# ---------------------------------------------------------------------------
# Test 3: target without existing hooks block — only valid hooks created
# ---------------------------------------------------------------------------
TMPDIR_PROJ3="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_HOME" "$TMPDIR_PROJ" "$TMPDIR_PROJ2" "$TMPDIR_PROJ3"' EXIT

mkdir -p "$TMPDIR_PROJ3/.claude"
echo '{"permissions":{"allow":[]}}' > "$TMPDIR_PROJ3/.claude/settings.json"
git -C "$TMPDIR_PROJ3" init -q
git -C "$TMPDIR_PROJ3" commit --allow-empty -m "init" -q

DIDIO_HOME="$TMPDIR_HOME" bash "$SYNC_SCRIPT" "$TMPDIR_PROJ3" >/dev/null 2>&1 || true

if grep -qF '{{' "$TMPDIR_PROJ3/.claude/settings.json" 2>/dev/null; then
  fail "boundary (no hooks block): '{{' leaked into target"
else
  pass "boundary (no hooks block): no '{{' in target settings.json"
fi

if python3 -m json.tool "$TMPDIR_PROJ3/.claude/settings.json" >/dev/null 2>&1; then
  pass "boundary: target settings.json is valid JSON"
else
  fail "boundary: target settings.json is not valid JSON"
fi

# ---------------------------------------------------------------------------
# Test 4: template already clean (no {{ hooks) — all hooks merge normally
# ---------------------------------------------------------------------------
TMPDIR_HOME2="$(mktemp -d)"
TMPDIR_PROJ4="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_HOME" "$TMPDIR_PROJ" "$TMPDIR_PROJ2" "$TMPDIR_PROJ3" "$TMPDIR_HOME2" "$TMPDIR_PROJ4"' EXIT

mkdir -p "$TMPDIR_HOME2/templates/.claude"
cat > "$TMPDIR_HOME2/templates/.claude/settings.json" <<'JSON'
{
  "permissions": {"allow": []},
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "*",
        "hooks": [
          {"type": "command", "command": "/usr/local/bin/hook-a.sh"},
          {"type": "command", "command": "/usr/local/bin/hook-b.sh"}
        ]
      }
    ]
  }
}
JSON

mkdir -p "$TMPDIR_PROJ4/.claude"
cp "$FIXTURE_CLEAN" "$TMPDIR_PROJ4/.claude/settings.json"
git -C "$TMPDIR_PROJ4" init -q
git -C "$TMPDIR_PROJ4" commit --allow-empty -m "init" -q

DIDIO_HOME="$TMPDIR_HOME2" bash "$SYNC_SCRIPT" "$TMPDIR_PROJ4" >/dev/null 2>&1 || true

ADDED_HOOKS=$(python3 -c "
import json
with open('$TMPDIR_PROJ4/.claude/settings.json') as f:
    d = json.load(f)
hooks = d.get('hooks', {}).get('PreToolUse', [])
cmds = [h.get('command','') for m in hooks for h in m.get('hooks',[])]
print(len(cmds))
" 2>/dev/null || echo 0)

if [[ "$ADDED_HOOKS" -ge 2 ]]; then
  pass "clean template: all valid hooks merged (got $ADDED_HOOKS)"
else
  fail "clean template: expected >=2 hooks merged, got $ADDED_HOOKS"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
