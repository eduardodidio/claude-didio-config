#!/usr/bin/env bash
# tests/F14-commands-smoke.sh — Structural smoke for F14 commands.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
PASS=0
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1))
  else
    echo "  ✗ $desc"
    FAIL=$((FAIL+1))
  fi
}

# --- 1. File pairs exist + identical ---
for cmd in brainstorm research product-brief; do
  check "templates/$cmd exists"    test -f "templates/.claude/commands/$cmd.md"
  check ".claude/$cmd exists"      test -f ".claude/commands/$cmd.md"
  check "$cmd template == .claude" diff -q "templates/.claude/commands/$cmd.md" ".claude/commands/$cmd.md"
done

# --- 2. Header YAML + no spawn ---
for cmd in brainstorm research product-brief; do
  f="templates/.claude/commands/$cmd.md"
  check "$cmd has YAML frontmatter"  bash -c "head -1 '$f' | grep -q '^---$'"
  check "$cmd has description:"      grep -q 'description:' "$f"
  check "$cmd no spawn-agent"        bash -c "! grep -q 'spawn-agent\|didio run-wave' '$f'"
done

# --- 3. Output dir per command ---
check "brainstorm → brainstorms/"    grep -q 'claude-didio-out/brainstorms' "templates/.claude/commands/brainstorm.md"
check "research → research/"         grep -q 'claude-didio-out/research'    "templates/.claude/commands/research.md"
check "product-brief → prd-drafts/"  grep -q 'claude-didio-out/prd-drafts'  "templates/.claude/commands/product-brief.md"

# --- 4. brainstorm specifics (AC1) ---
B="templates/.claude/commands/brainstorm.md"
check "brainstorm: ### Direção"              grep -q '### Direção'             "$B"
check "brainstorm: Quem ganha / Quem perde"  grep -q 'Quem ganha / Quem perde' "$B"
check "brainstorm: Esforço estimado"         grep -q 'Esforço estimado'        "$B"
check "brainstorm: Risco principal"          grep -q 'Risco principal'         "$B"
check "brainstorm: Pré-condição"             grep -q 'Pré-condição'            "$B"
check "brainstorm: 3 a 5 direções"           bash -c "grep -qE 'entre 3 e 5|3 a 5|3.{1,5}5 dire' '$B'"

# --- 5. research specifics (AC2, AC5) ---
R="templates/.claude/commands/research.md"
check "research: ## Sources"           grep -q '## Sources'        "$R"
check "research: ## Key findings"      grep -q '## Key findings'   "$R"
check "research: ## Open questions"    grep -q '## Open questions'  "$R"
check "research: web_search_budget"    grep -q 'web_search_budget'  "$R"
check "research: web_fetch_budget"     grep -q 'web_fetch_budget'   "$R"
check "research: Budget used:"         grep -q 'Budget used:'       "$R"
check "research: indisponível branch"  grep -qi 'indispon'          "$R"

# --- 6. product-brief specifics (AC3, AC4) ---
P="templates/.claude/commands/product-brief.md"
check "pb: ## Topic"                        grep -q '## Topic'                        "$P"
check "pb: ## Brainstorm directions chosen" grep -q '## Brainstorm directions chosen' "$P"
check "pb: ## Research highlights"          grep -q '## Research highlights'          "$P"
check "pb: ## Open questions"               grep -q '## Open questions'               "$P"
check "pb: ## Suggested next step"          grep -q '## Suggested next step'          "$P"
check "pb: skipped brainstorm fallback"     grep -q '_(skipped'                       "$P"
check "pb: detects F11 (elicit-prd.md)"     grep -q "elicit-prd.md"                  "$P"
check "pb: no write to tasks/features/"     bash -c "! grep -nE 'Write\\(.*tasks/features|cp .* tasks/features' '$P'"
check "pb: uses AskUserQuestion"            grep -q 'AskUserQuestion'                 "$P"

# --- 7. Menu (didio.md) ---
M="templates/.claude/commands/didio.md"
check "menu: brainstorm entry present"     grep -qE '^16\..*Brainstorm|^16\..*/brainstorm|^17\..*Brainstorm|^17\..*/brainstorm|/brainstorm' "$M"
check "menu: research entry present"       grep -qE '^17\..*Research|^17\..*/research|^18\..*Research|^18\..*/research|/research'           "$M"
check "menu: product-brief entry present"  grep -qE '^18\..*Product brief|^18\..*/product-brief|^19\..*Product brief|^19\..*/product-brief|/product-brief' "$M"
check "menu: mentions opt-in/greenfield"   grep -qiE 'opt-in|greenfield' "$M"
check "menu: template == .claude"          diff -q "$M" ".claude/commands/didio.md"

# --- 8. Permissions front-loaded (AC8) ---
check "settings.json: WebSearch+WebFetch+AskUserQuestion in allow" python3 -c '
import json,sys
cfg = json.load(open("templates/.claude/settings.json"))
allow = set(cfg["permissions"]["allow"])
needed = {"WebSearch","WebFetch","AskUserQuestion"}
sys.exit(0 if needed.issubset(allow) else 1)
'

# --- 9. Config block (AC5 part) ---
check "didio.config.json: research block with budgets" python3 -c '
import json,sys
cfg = json.load(open("templates/didio.config.json"))
r = cfg.get("research", {})
sys.exit(0 if r.get("web_search_budget") == 5 and r.get("web_fetch_budget") == 3 else 1)
'

echo ""
echo "F14 smoke: $PASS checks passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
