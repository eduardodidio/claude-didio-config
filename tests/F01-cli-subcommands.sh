#!/usr/bin/env bash
# F01-cli-subcommands.sh — smoke tests for the `didio compile-skills` and
# `didio providers` subcommands wired in bin/didio (F01-T12).
# Usage: bash tests/F01-cli-subcommands.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$SCRIPT_DIR/../bin" && pwd)"
DIDIO="$BIN_DIR/didio"

TOTAL_PASS=0
TOTAL_FAIL=0

_pass() { echo "  [PASS] $1"; (( TOTAL_PASS++ )) || true; }
_fail() { echo "  [FAIL] $1"; (( TOTAL_FAIL++ )) || true; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

export DIDIO_HOME="$BIN_DIR/.."

# ─── Stub PATH: provide a fake 'claude' but no 'codex' ────────────────────────
STUBBIN="$TMP/stubbin"
mkdir -p "$STUBBIN"
cat > "$STUBBIN/claude" <<'EOF'
#!/usr/bin/env bash
echo "stub-claude"
EOF
chmod +x "$STUBBIN/claude"
# Deliberately no 'codex' stub.

# ─── Claude-only config (no role uses codex) ──────────────────────────────────
CLAUDE_ONLY="$TMP/claude-only"
mkdir -p "$CLAUDE_ONLY"
cat > "$CLAUDE_ONLY/didio.config.json" <<'EOF'
{
  "providers": {
    "claude": { "bin": "claude", "default": true },
    "codex": { "bin": "codex" }
  },
  "models": {
    "developer": { "model": "sonnet", "fallback": "haiku" },
    "techlead": { "model": "sonnet", "fallback": "haiku" }
  }
}
EOF

# ─── Codex-using config (a role is assigned to codex) ─────────────────────────
WITH_CODEX="$TMP/with-codex"
mkdir -p "$WITH_CODEX"
cat > "$WITH_CODEX/didio.config.json" <<'EOF'
{
  "providers": {
    "claude": { "bin": "claude", "default": true },
    "codex": { "bin": "codex" }
  },
  "models": {
    "developer": { "provider": "codex", "model": "gpt-5-codex" },
    "techlead": { "model": "sonnet", "fallback": "haiku" }
  }
}
EOF

# ─── didio --help lists both new subcommands ──────────────────────────────────
HELP_OUT="$(PATH="$STUBBIN:$PATH" "$DIDIO" --help 2>&1)"
if echo "$HELP_OUT" | grep -q "compile-skills"; then
  _pass "didio --help lists compile-skills"
else
  _fail "didio --help lists compile-skills"
fi
if echo "$HELP_OUT" | grep -q "didio providers"; then
  _pass "didio --help lists providers"
else
  _fail "didio --help lists providers"
fi

# ─── Unknown subcommand still exits 1 with original message ───────────────────
UNKNOWN_OUT="$(PATH="$STUBBIN:$PATH" "$DIDIO" totally-bogus-subcommand 2>&1)"
UNKNOWN_RC=$?
if [[ "$UNKNOWN_RC" -ne 0 ]] && echo "$UNKNOWN_OUT" | grep -q "unknown subcommand"; then
  _pass "unknown subcommand exits non-zero with original message"
else
  _fail "unknown subcommand exits non-zero with original message (rc=$UNKNOWN_RC, out=$UNKNOWN_OUT)"
fi

# ─── didio providers list shows claude + codex with resolution ────────────────
LIST_OUT="$(cd "$CLAUDE_ONLY" && PATH="$STUBBIN:$PATH" PROJECT_ROOT="$CLAUDE_ONLY" "$DIDIO" providers list 2>&1)"
LIST_RC=$?
if [[ "$LIST_RC" -eq 0 ]] && echo "$LIST_OUT" | grep -q "^claude -> claude (found)" && echo "$LIST_OUT" | grep -q "^codex -> codex (missing)"; then
  _pass "providers list shows claude (found) and codex (missing)"
else
  _fail "providers list shows claude (found) and codex (missing) (rc=$LIST_RC, out=$LIST_OUT)"
fi

# ─── Claude-only config: providers validate ignores absent codex, exits 0 ─────
PATH="$STUBBIN:$PATH" PROJECT_ROOT="$CLAUDE_ONLY" "$DIDIO" providers validate >/dev/null 2>&1
VALIDATE_CLAUDE_ONLY_RC=$?
if [[ "$VALIDATE_CLAUDE_ONLY_RC" -eq 0 ]]; then
  _pass "providers validate exits 0 for claude-only config (codex unused)"
else
  _fail "providers validate exits 0 for claude-only config (got rc=$VALIDATE_CLAUDE_ONLY_RC)"
fi

# ─── Codex-using config, codex missing from PATH: validate exits 1 naming codex
VALIDATE_CODEX_OUT="$(PATH="$STUBBIN:$PATH" PROJECT_ROOT="$WITH_CODEX" "$DIDIO" providers validate 2>&1)"
VALIDATE_CODEX_RC=$?
if [[ "$VALIDATE_CODEX_RC" -ne 0 ]] && echo "$VALIDATE_CODEX_OUT" | grep -q "codex"; then
  _pass "providers validate exits 1 and names codex when role uses it but binary is missing"
else
  _fail "providers validate exits 1 and names codex (rc=$VALIDATE_CODEX_RC, out=$VALIDATE_CODEX_OUT)"
fi

# ─── didio compile-skills --dry-run dispatches without writing ────────────────
COMPILE_OUT="$(PATH="$STUBBIN:$PATH" "$DIDIO" compile-skills --dry-run 2>&1)"
COMPILE_RC=$?
if [[ "$COMPILE_RC" -eq 0 ]]; then
  _pass "didio compile-skills --dry-run dispatches and exits 0"
else
  _fail "didio compile-skills --dry-run dispatches and exits 0 (rc=$COMPILE_RC, out=$COMPILE_OUT)"
fi

echo ""
echo "Total: $TOTAL_PASS passed, $TOTAL_FAIL failed"

if (( TOTAL_FAIL > 0 )); then
  exit 1
fi
exit 0
