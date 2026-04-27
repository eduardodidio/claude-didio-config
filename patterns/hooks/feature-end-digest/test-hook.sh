#!/usr/bin/env bash
# Hermetic test for patterns/hooks/feature-end-digest/hook.sh
# Covers: done+QA, no-QA, planned, kill-switch, token-redaction, idempotence.
# Run: bash patterns/hooks/feature-end-digest/test-hook.sh
# No set -e — custom assert harness; failures accumulate, summary at end.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HOOK="$SCRIPT_DIR/hook.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT

HUB="$SANDBOX/hub"
PROJ="$SANDBOX/proj"

PASS_COUNT=0
FAIL_COUNT=0

# ---------------------------------------------------------------------------
# Assert helpers
# ---------------------------------------------------------------------------

assert_eq() {
  local name="$1" exp="$2" got="$3"
  if [ "$exp" = "$got" ]; then
    echo "OK  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL $name: expected [$exp] got [$got]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_contains() {
  local name="$1" file="$2" needle="$3"
  if grep -qF "$needle" "$file" 2>/dev/null; then
    echo "OK  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL $name: [$needle] not found in [$file]"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_not_contains() {
  local name="$1" file="$2" needle="$3"
  if ! grep -qF "$needle" "$file" 2>/dev/null; then
    echo "OK  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL $name: [$needle] found in [$file] (should be absent)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ---------------------------------------------------------------------------
# Sandbox helpers
# ---------------------------------------------------------------------------

reset_sandbox() {
  rm -rf "$PROJ" "$HUB"

  mkdir -p "$HUB/projects"
  cat > "$HUB/projects/registry.yaml" << YAML
version: 1
projects:
  - name: test-proj
    path: $PROJ
    status: active
YAML

  mkdir -p \
    "$PROJ/tasks/features/F90-foo" \
    "$PROJ/memory/agent-learnings" \
    "$PROJ/memory/_pending-digest" \
    "$PROJ/.claude/skills/new-skill" \
    "$PROJ/patterns/snippets/new-snippet"

  # Bare git repo so collect_new_learnings git calls don't error
  git -C "$PROJ" init -q 2>/dev/null
  git -C "$PROJ" config user.email "test@test.com" 2>/dev/null
  git -C "$PROJ" config user.name "Test" 2>/dev/null

  cp "$FIXTURES_DIR/fixture-readme-done.md"        "$PROJ/tasks/features/F90-foo/F90-README.md"
  cp "$FIXTURES_DIR/fixture-qa-report.md"          "$PROJ/tasks/features/F90-foo/qa-report-20260426T0000Z.md"
  cp "$FIXTURES_DIR/fixture-developer-learnings.md" "$PROJ/memory/agent-learnings/developer.md"

  # Pattern snippet README (inline — not a fixture file)
  printf -- '---\ntype: snippet\n---\n# new-snippet\n' \
    > "$PROJ/patterns/snippets/new-snippet/README.md"
}

count_drops() {
  find "$PROJ/memory/_pending-digest" -name 'F90-*.md' 2>/dev/null \
    | wc -l | tr -d ' '
}

invoke_hook() {
  CLAUDE_PROJECT_DIR="$PROJ" \
  CLAUDE_PROJECT_NAME="test-proj" \
  SECOND_BRAIN_HUB="$HUB" \
  HOME="$SANDBOX" \
  bash "$HOOK" 2>/dev/null
}

# ---------------------------------------------------------------------------
# SMOKE: syntax check
# ---------------------------------------------------------------------------

echo "SMOKE: bash -n"
bash -n "$HOOK" 2>/dev/null
assert_eq "smoke:bash-n-hook" "0" "$?"

# ---------------------------------------------------------------------------
# TEST 1: done + recent QA → drop created
# ---------------------------------------------------------------------------

echo ""
echo "TEST 1: done + recent QA"
reset_sandbox
invoke_hook
assert_eq "T1:drop-count" "1" "$(count_drops)"

# ---------------------------------------------------------------------------
# TEST 2: QA report too old → no drop
# ---------------------------------------------------------------------------

echo ""
echo "TEST 2: QA report too old"
reset_sandbox
touch -t 200001010000 "$PROJ/tasks/features/F90-foo/qa-report-20260426T0000Z.md"
invoke_hook
assert_eq "T2:no-drop" "0" "$(count_drops)"

# ---------------------------------------------------------------------------
# TEST 3: Status planned → no drop
# ---------------------------------------------------------------------------

echo ""
echo "TEST 3: Status planned"
reset_sandbox
cp "$FIXTURES_DIR/fixture-readme-planned.md" "$PROJ/tasks/features/F90-foo/F90-README.md"
invoke_hook
assert_eq "T3:no-drop" "0" "$(count_drops)"

# ---------------------------------------------------------------------------
# TEST 4: Kill switch → no drop
# ---------------------------------------------------------------------------

echo ""
echo "TEST 4: kill switch"
reset_sandbox
DIDIO_DIGEST_DISABLED=1 \
CLAUDE_PROJECT_DIR="$PROJ" \
CLAUDE_PROJECT_NAME="test-proj" \
SECOND_BRAIN_HUB="$HUB" \
HOME="$SANDBOX" \
bash "$HOOK" 2>/dev/null
assert_eq "T4:no-drop" "0" "$(count_drops)"

# ---------------------------------------------------------------------------
# TEST 5: Token redaction — drop exists, token redacted, raw absent
# ---------------------------------------------------------------------------

echo ""
echo "TEST 5: token redaction"
reset_sandbox
cp "$FIXTURES_DIR/fixture-with-token.md" "$PROJ/tasks/features/F90-foo/qa-report-20260426T0000Z.md"
invoke_hook
T5_COUNT="$(count_drops)"
assert_eq "T5:drop-count" "1" "$T5_COUNT"
if [ "$T5_COUNT" = "1" ]; then
  T5_DROP="$(find "$PROJ/memory/_pending-digest" -name 'F90-*.md' 2>/dev/null | head -1)"
  assert_contains     "T5:redacted-token" "$T5_DROP" "[REDACTED-TOKEN]"
  assert_not_contains "T5:no-raw-token"   "$T5_DROP" "sk-AAAA"
fi

# ---------------------------------------------------------------------------
# TEST 6: Idempotence — fake date fixes timestamp; second run skips
# ---------------------------------------------------------------------------

echo ""
echo "TEST 6: idempotence"
reset_sandbox

# Capture real date path before injecting fake into PATH
_REAL_DATE="$(command -v date)"

mkdir -p "$SANDBOX/bin"
cat > "$SANDBOX/bin/date" << DATEEOF
#!/usr/bin/env bash
for arg in "\$@"; do
  if [ "\$arg" = "+%Y%m%dT%H%M%SZ" ]; then
    printf '20260101T000000Z\n'
    exit 0
  fi
done
exec "$_REAL_DATE" "\$@"
DATEEOF
chmod +x "$SANDBOX/bin/date"

PATH="$SANDBOX/bin:$PATH" \
CLAUDE_PROJECT_DIR="$PROJ" \
CLAUDE_PROJECT_NAME="test-proj" \
SECOND_BRAIN_HUB="$HUB" \
HOME="$SANDBOX" \
bash "$HOOK" 2>/dev/null

PATH="$SANDBOX/bin:$PATH" \
CLAUDE_PROJECT_DIR="$PROJ" \
CLAUDE_PROJECT_NAME="test-proj" \
SECOND_BRAIN_HUB="$HUB" \
HOME="$SANDBOX" \
bash "$HOOK" 2>/dev/null

assert_eq "T6:idempotent-count" "1" "$(count_drops)"

# ---------------------------------------------------------------------------
# TEST 7: Anthropic token (sk-ant-) redaction — new pattern from B2 fix
# ---------------------------------------------------------------------------

echo ""
echo "TEST 7: Anthropic token (sk-ant-) redaction"
reset_sandbox
# Replace QA report with one containing an Anthropic-style token
cat > "$PROJ/tasks/features/F90-foo/qa-report-20260426T0000Z.md" << 'ANTHEOF'
---
feature: F90
---
## Anomalies
- Found Anthropic API key sk-ant-api03-AAABBBCCCDDDEEEFFFGGG1234567890 in config.yaml
ANTHEOF
invoke_hook
T7_COUNT="$(count_drops)"
assert_eq "T7:drop-count" "1" "$T7_COUNT"
if [ "$T7_COUNT" = "1" ]; then
  T7_DROP="$(find "$PROJ/memory/_pending-digest" -name 'F90-*.md' 2>/dev/null | head -1)"
  assert_contains     "T7:redacted-token"   "$T7_DROP" "[REDACTED-TOKEN]"
  assert_not_contains "T7:no-raw-ant-key"   "$T7_DROP" "sk-ant-api03-"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "RESULT: $FAIL_COUNT/$TOTAL FAILED"
  exit 1
fi
echo "OK: $PASS_COUNT/$TOTAL cases"
exit 0
