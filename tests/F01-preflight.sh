#!/usr/bin/env bash
# F01-preflight.sh — preflight provider validation before a Wave (F01-T13).
#
# Verifies:
#   - didio-providers.sh validate-roles checks only the given roles' providers
#   - didio-run-wave.sh aborts (non-zero, no spawn) when a used provider's CLI
#     binary is missing
#   - Claude-only Waves are unaffected by a missing/absent codex binary
#   - mixed Waves correctly name whichever provider is missing
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1" >&2; FAIL=$((FAIL+1)); }

echo "== F01 preflight smoke =="

TMP=$(mktemp -d)
FIX_DIR="$TMP/tasks/features/F98-fixture"
mkdir -p "$FIX_DIR" "$TMP/fakebin"

# Config: developer -> claude (default), techlead -> codex
cat > "$TMP/didio.config.json" <<'EOF'
{
  "providers": {
    "claude": { "bin": "claude", "default": true },
    "codex": { "bin": "codex" }
  },
  "models": {
    "developer": { "model": "sonnet" },
    "techlead": { "provider": "codex", "model": "gpt-5-codex" }
  }
}
EOF

cat > "$FIX_DIR/F98-README.md" <<'EOF'
# F98 — fixture
- **Wave 0**: F98-T01
EOF
cat > "$FIX_DIR/F98-T01.md" <<'EOF'
# F98-T01 — fixture task
EOF

mkdir -p "$TMP/agents/prompts"
for role in developer techlead; do
  cat > "$TMP/agents/prompts/$role.md" <<'EOF'
{{USE_SECOND_BRAIN}}
{{DIDIO_CHECKPOINT}}
Fixture role prompt.
EOF
done

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Minimal fake `claude` binary always on PATH for these tests.
cat > "$TMP/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/fakebin/claude"

run_in_fixture() {
  # $1 = PATH to use, remaining args -> didio-run-wave.sh
  local fixture_path="$1"; shift
  (
    cd "$TMP"
    PATH="$fixture_path:/opt/homebrew/bin:/usr/bin:/bin" DIDIO_HOME="$PROJECT_ROOT" DIDIO_DRY_RUN=1 \
      bash "$PROJECT_ROOT/bin/didio-run-wave.sh" "$@"
  )
}

# --- Scenario: providers validate-roles, role-scoped ---
echo "[1] providers validate-roles — scoped to given roles"
(
  cd "$TMP"
  PATH="$TMP/fakebin:$PATH" DIDIO_HOME="$PROJECT_ROOT" \
    bash "$PROJECT_ROOT/bin/didio-providers.sh" validate-roles developer >/dev/null 2>&1
)
rc=$?
[[ $rc -eq 0 ]] && ok "developer (claude) passes when claude on PATH" \
  || fail "developer (claude) should pass (rc=$rc)"

(
  cd "$TMP"
  PATH="$TMP/fakebin:$PATH" DIDIO_HOME="$PROJECT_ROOT" \
    bash "$PROJECT_ROOT/bin/didio-providers.sh" validate-roles techlead >/dev/null 2>&1
)
rc=$?
[[ $rc -ne 0 ]] && ok "techlead (codex) fails when codex absent" \
  || fail "techlead (codex) should fail (rc=$rc)"

# --- Scenario: happy path — claude-only Wave, claude present ---
echo "[2] happy path — claude-only Wave, claude on PATH"
out=$(run_in_fixture "$TMP/fakebin" F98 0 developer 2>&1)
rc=$?
[[ $rc -eq 0 ]] && ok "Wave proceeds (rc=0)" || fail "Wave should proceed (rc=$rc): $out"
echo "$out" | grep -q 'DRY_RUN' && ok "agent was spawned" || fail "agent spawn not observed"

# --- Scenario: edge case — claude-only Wave, codex absent (must NOT block) ---
echo "[3] edge case — codex absent but unused by this Wave's role"
# fakebin has only claude; codex is not on PATH anywhere.
out=$(run_in_fixture "$TMP/fakebin" F98 0 developer 2>&1)
rc=$?
[[ $rc -eq 0 ]] && ok "Wave proceeds despite missing codex (rc=0)" \
  || fail "Wave should not be blocked by unused codex (rc=$rc): $out"

# --- Scenario: error — role uses codex, codex absent -> abort, no spawn ---
echo "[4] error scenario — techlead role needs codex, codex absent"
out=$(run_in_fixture "$TMP/fakebin" F98 0 techlead 2>&1)
rc=$?
[[ $rc -ne 0 ]] && ok "Wave aborts (rc=$rc)" || fail "Wave should abort (rc=$rc)"
echo "$out" | grep -qi 'codex' && ok "message names codex" || fail "message does not name codex: $out"
echo "$out" | grep -q 'DRY_RUN' && fail "agent was spawned despite preflight failure" \
  || ok "no agent spawned"

# --- Scenario: boundary — claude role, claude absent -> abort naming claude ---
echo "[5] boundary — developer role needs claude, claude absent (codex present)"
mkdir -p "$TMP/fakebin2"
cat > "$TMP/fakebin2/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TMP/fakebin2/codex"
out=$(run_in_fixture "$TMP/fakebin2" F98 0 developer 2>&1)
rc=$?
[[ $rc -ne 0 ]] && ok "Wave aborts (rc=$rc)" || fail "Wave should abort (rc=$rc)"
echo "$out" | grep -qi 'claude' && ok "message names claude" || fail "message does not name claude: $out"
echo "$out" | grep -q 'DRY_RUN' && fail "agent was spawned despite preflight failure" \
  || ok "no agent spawned"

echo "== Result: $PASS passed, $FAIL failed =="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
