#!/usr/bin/env bash
# F01-T03 — Neutral skill format smoke test
# Verifica skills/SPEC.md + skills/_example.md: front-matter, override-block
# balance, sentinel preservation, e detecção de blocks desbalanceados.

set -uo pipefail

SKILLS_DIR="${DIDIO_HOME:-$HOME/.claude-didio-config}/skills"
PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=== F01 Skill Spec Smoke Test ==="
echo "Skills dir: $SKILLS_DIR"
echo ""

# --- SPEC.md exists ---
if [[ -f "$SKILLS_DIR/SPEC.md" ]]; then
  ok "SPEC.md exists"
else
  bad "SPEC.md missing"
fi

# --- _example.md exists ---
EXAMPLE="$SKILLS_DIR/_example.md"
if [[ -f "$EXAMPLE" ]]; then
  ok "_example.md exists"
else
  bad "_example.md missing"
fi

# --- front-matter required keys (happy path) ---
check_frontmatter() {
  local file="$1"
  python3 - "$file" <<'EOF'
import sys, re
path = sys.argv[1]
text = open(path).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
if not m:
    sys.exit(1)
fm = m.group(1)
required = ["name:", "description:", "kind:", "targets:"]
for key in required:
    if not re.search(r"^" + re.escape(key), fm, re.M):
        sys.exit(1)
sys.exit(0)
EOF
}

if check_frontmatter "$EXAMPLE"; then
  ok "_example.md front-matter has required keys (name, description, kind, targets)"
else
  bad "_example.md front-matter missing required keys"
fi

# --- override blocks balanced (happy path) ---
check_balanced() {
  local file="$1"
  python3 - "$file" <<'EOF'
import sys, re
text = open(sys.argv[1]).read()
opens = re.findall(r"<!-- didio:(\w+) -->", text)
closes = re.findall(r"<!-- /didio:(\w+) -->", text)
sys.exit(0 if sorted(opens) == sorted(closes) else 1)
EOF
}

if check_balanced "$EXAMPLE"; then
  ok "_example.md override blocks are balanced"
else
  bad "_example.md override blocks are unbalanced"
fi

# --- both didio:claude and didio:codex blocks present ---
if grep -q '<!-- didio:claude -->' "$EXAMPLE" && grep -q '<!-- /didio:claude -->' "$EXAMPLE" \
  && grep -q '<!-- didio:codex -->' "$EXAMPLE" && grep -q '<!-- /didio:codex -->' "$EXAMPLE"; then
  ok "_example.md has both claude and codex override blocks, opened and closed"
else
  bad "_example.md missing claude/codex override blocks"
fi

# --- sentinels survive verbatim ---
if grep -q '{{USE_SECOND_BRAIN}}' "$EXAMPLE" && grep -q '{{DIDIO_CHECKPOINT}}' "$EXAMPLE"; then
  ok "_example.md retains sentinels {{USE_SECOND_BRAIN}} and {{DIDIO_CHECKPOINT}} verbatim"
else
  bad "_example.md missing sentinels"
fi

# --- edge case: targets: [claude] only, no codex block, is valid ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/claude-only.md" <<'EOF'
---
name: claude-only-skill
description: Skill targeting only Claude
kind: command
targets: [claude]
---
Shared line.

<!-- didio:claude -->
Claude-only line.
<!-- /didio:claude -->
EOF

if check_frontmatter "$TMPDIR/claude-only.md" && check_balanced "$TMPDIR/claude-only.md"; then
  ok "edge case: targets: [claude] only (no codex block) is valid"
else
  bad "edge case: targets: [claude] only should be valid"
fi

# --- error scenario: unbalanced override block is detected ---
cat > "$TMPDIR/unbalanced.md" <<'EOF'
---
name: unbalanced-skill
description: Skill with an unbalanced override block
kind: command
targets: [claude, codex]
---
<!-- didio:claude -->
Open without close.
EOF

if check_balanced "$TMPDIR/unbalanced.md"; then
  bad "error scenario: unbalanced override block should have been detected"
else
  ok "error scenario: unbalanced override block correctly detected"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
