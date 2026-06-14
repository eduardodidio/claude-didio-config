#!/usr/bin/env bash
# F01-T06 — Skill migration smoke test
# Verifica que .claude/commands/*.md, agents/prompts/*.md e .claude/agents/*.md
# foram portados para skills/*.md com front-matter válido, override blocks
# balanceados e sentinelas preservadas verbatim.

set -uo pipefail

DIDIO_HOME_DIR="${DIDIO_HOME:-$HOME/.claude-didio-config}"
SKILLS_DIR="$DIDIO_HOME_DIR/skills"
PASS=0
FAIL=0

ok()  { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad() { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

echo "=== F01 Skill Migration Smoke Test ==="
echo "Skills dir: $SKILLS_DIR"
echo ""

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

check_balanced() {
  python3 - "$1" <<'EOF'
import sys, re
text = open(sys.argv[1]).read()
opens = re.findall(r"<!-- didio:(\w+) -->", text)
closes = re.findall(r"<!-- /didio:(\w+) -->", text)
sys.exit(0 if sorted(opens) == sorted(closes) else 1)
EOF
}

get_field() {
  # get_field <file> <key> -> value of front-matter key (raw line, trimmed)
  python3 - "$1" "$2" <<'EOF'
import sys, re
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
fm = m.group(1) if m else ""
for line in fm.splitlines():
    mm = re.match(r"^" + re.escape(sys.argv[2]) + r":\s*(.*)$", line)
    if mm:
        print(mm.group(1).strip())
        break
EOF
}

# --- MIGRATION.md exists ---
if [[ -f "$SKILLS_DIR/MIGRATION.md" ]]; then
  ok "MIGRATION.md exists"
else
  bad "MIGRATION.md missing"
fi

# --- happy path: every .claude/commands/*.md and agents/prompts/*.md has a
#     corresponding skills/*.md with valid front-matter ---
for f in "$DIDIO_HOME_DIR"/.claude/commands/*.md; do
  name=$(basename "$f" .md)
  skill="$SKILLS_DIR/$name.md"
  if [[ -f "$skill" ]] && check_frontmatter "$skill"; then
    ok "command '$name' -> skills/$name.md (valid front-matter)"
  else
    bad "command '$name' missing skill or invalid front-matter"
  fi
  kind=$(get_field "$skill" "kind")
  [[ "$kind" == "command" ]] && ok "  kind: command for $name" || bad "  expected kind: command for $name, got '$kind'"
done

for f in "$DIDIO_HOME_DIR"/agents/prompts/*.md; do
  base=$(basename "$f" .md)
  name="$base"
  [[ "$base" == "_checkpoint-block" ]] && name="checkpoint-block"
  skill="$SKILLS_DIR/$name.md"
  if [[ -f "$skill" ]] && check_frontmatter "$skill"; then
    ok "role-prompt '$base' -> skills/$name.md (valid front-matter)"
  else
    bad "role-prompt '$base' missing skill or invalid front-matter"
  fi
  kind=$(get_field "$skill" "kind")
  [[ "$kind" == "role-prompt" ]] && ok "  kind: role-prompt for $name" || bad "  expected kind: role-prompt for $name, got '$kind'"

  # sentinel preservation: grep count must match source
  for sentinel in '{{USE_SECOND_BRAIN}}' '{{DIDIO_CHECKPOINT}}'; do
    src_count=$(grep -c -- "$sentinel" "$f" || true)
    dst_count=$(grep -c -- "$sentinel" "$skill" || true)
    if [[ "$src_count" == "$dst_count" ]]; then
      ok "  sentinel $sentinel count matches for $name ($src_count)"
    else
      bad "  sentinel $sentinel count mismatch for $name (src=$src_count dst=$dst_count)"
    fi
  done
done

# --- edge case: subagent skills carry targets: [claude] (no codex target) ---
for f in "$DIDIO_HOME_DIR"/.claude/agents/*.md; do
  name=$(basename "$f" .md)
  skill="$SKILLS_DIR/$name-agent.md"
  if [[ -f "$skill" ]] && check_frontmatter "$skill"; then
    ok "subagent '$name' -> skills/$name-agent.md (valid front-matter)"
  else
    bad "subagent '$name' missing skill or invalid front-matter"
  fi
  kind=$(get_field "$skill" "kind")
  targets=$(get_field "$skill" "targets")
  [[ "$kind" == "subagent" ]] && ok "  kind: subagent for $name" || bad "  expected kind: subagent for $name, got '$kind'"
  [[ "$targets" == "[claude]" ]] && ok "  targets: [claude] for $name" || bad "  expected targets: [claude] for $name, got '$targets'"
done

# --- override blocks balanced across all generated skill files ---
for skill in "$SKILLS_DIR"/*.md; do
  base=$(basename "$skill")
  [[ "$base" == "SPEC.md" ]] && continue
  if check_balanced "$skill"; then
    ok "override blocks balanced in $base"
  else
    bad "override blocks UNBALANCED in $base"
  fi
done

# --- error scenario: source file with no front-matter description still
#     yields a valid skill (description derived from H1 / filename) ---
# agents/prompts/*.md have no front-matter at all; verify their skills still
# got a non-empty description.
for f in "$DIDIO_HOME_DIR"/agents/prompts/*.md; do
  base=$(basename "$f" .md)
  name="$base"
  [[ "$base" == "_checkpoint-block" ]] && name="checkpoint-block"
  skill="$SKILLS_DIR/$name.md"
  desc=$(get_field "$skill" "description")
  if [[ -n "$desc" ]]; then
    ok "  derived non-empty description for $name (no source front-matter)"
  else
    bad "  empty description for $name (source has no front-matter)"
  fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ $FAIL -eq 0 ]]
