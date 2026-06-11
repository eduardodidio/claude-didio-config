#!/usr/bin/env bash
# F27-selector — structural test for /bmad selector (F27-T11, AC3/AC8)
#
# Asserts templates/commands/bmad.md:
#  - validates the gf/bf argument (AskUserQuestion fallback)
#  - chains the correct GF and BF upstream sequences (each /bmad-* by name)
#  - has an explicit confirmation pause between upstream and downstream
#  - references existing gates (readiness/TEA) without reimplementing them
#  - does not duplicate sub-command logic (no "## Step" sections)
# Also asserts docs/diagrams/F27-journey.mmd is a valid Mermaid flowchart
# with swimlanes.
#
# Run: bash bin/tests/F27-selector.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BMAD_MD="$REPO_ROOT/templates/commands/bmad.md"
JOURNEY_MMD="$REPO_ROOT/docs/diagrams/F27-journey.mmd"

PASS=0
FAIL=0

pass() { echo "[PASS] $1"; PASS=$((PASS+1)); }
fail() { echo "[FAIL] $1"; FAIL=$((FAIL+1)); }

[[ -f "$BMAD_MD" ]] || { echo "FATAL: $BMAD_MD missing"; exit 1; }
[[ -f "$JOURNEY_MMD" ]] || { echo "FATAL: $JOURNEY_MMD missing"; exit 1; }

# ---------------------------------------------------------------------------
# Argument validation / fallback
# ---------------------------------------------------------------------------
if grep -qi 'AskUserQuestion' "$BMAD_MD" && grep -qi 'greenfield\|brownfield' "$BMAD_MD"; then
  pass "argument validation falls back to AskUserQuestion"
else
  fail "no AskUserQuestion fallback for invalid/missing argument"
fi

# ---------------------------------------------------------------------------
# GF upstream sequence
# ---------------------------------------------------------------------------
GF_UPSTREAM=(
  bmad-generate-project-context
  bmad-brainstorm
  bmad-research
  bmad-create-product-brief
  bmad-create-prd
  bmad-create-ux-design
  bmad-create-architecture
  bmad-testarch-test-design
  bmad-create-epics-and-stories
)
gf_ok=true
for cmd in "${GF_UPSTREAM[@]}"; do
  grep -q "$cmd" "$BMAD_MD" || { gf_ok=false; echo "  missing: $cmd"; }
done
$gf_ok && pass "GF upstream sequence references all expected /bmad-* steps" \
        || fail "GF upstream sequence missing one or more /bmad-* steps"

# ---------------------------------------------------------------------------
# BF upstream sequence
# ---------------------------------------------------------------------------
BF_UPSTREAM=(
  bmad-generate-project-context
  bmad-create-prd
  bmad-create-ux-design
  bmad-create-architecture
  bmad-testarch-test-design
  bmad-create-epics-and-stories
)
bf_ok=true
for cmd in "${BF_UPSTREAM[@]}"; do
  grep -q "$cmd" "$BMAD_MD" || { bf_ok=false; echo "  missing: $cmd"; }
done
$bf_ok && pass "BF upstream sequence references all expected /bmad-* steps" \
        || fail "BF upstream sequence missing one or more /bmad-* steps"

# Negative: BF block must NOT include brainstorm/research/product-brief
BF_SECTION=$(awk '/Se `brownfield`/{flag=1} /## Gate de readiness/{flag=0} flag' "$BMAD_MD")
if echo "$BF_SECTION" | grep -qE 'bmad-brainstorm|bmad-research|bmad-create-product-brief'; then
  fail "BF upstream section incorrectly includes GF-only steps (brainstorm/research/product-brief)"
else
  pass "BF upstream section does not include GF-only steps"
fi

# ---------------------------------------------------------------------------
# DOWNSTREAM (shared) sequence
# ---------------------------------------------------------------------------
DOWNSTREAM=(
  bmad-testarch-framework
  bmad-testarch-ci
  bmad-sprint-planning
  bmad-create-story
  bmad-testarch-atdd
  bmad-dev-story
  bmad-code-review
  bmad-correct-course
  bmad-testarch-automate
  bmad-retrospective
)
down_ok=true
for cmd in "${DOWNSTREAM[@]}"; do
  grep -q "$cmd" "$BMAD_MD" || { down_ok=false; echo "  missing: $cmd"; }
done
$down_ok && pass "DOWNSTREAM sequence references all expected /bmad-* steps" \
          || fail "DOWNSTREAM sequence missing one or more /bmad-* steps"

# ---------------------------------------------------------------------------
# Confirmation pause between upstream and downstream
# ---------------------------------------------------------------------------
if grep -qiE 'AskUserQuestion' "$BMAD_MD" && grep -qiE 'pausa|confirma' "$BMAD_MD"; then
  pass "explicit confirmation pause present between upstream and downstream"
else
  fail "no explicit confirmation pause found"
fi

# ---------------------------------------------------------------------------
# Gate reuse (readiness / TEA), not reimplemented
# ---------------------------------------------------------------------------
if grep -q 'check-impl-readiness\|check-readiness' "$BMAD_MD" && grep -q 'testarch-test-design\|check-tests' "$BMAD_MD"; then
  pass "references readiness and TEA gates"
else
  fail "missing reference to readiness and/or TEA gate"
fi

# BLOCKED handling
if grep -qi 'BLOCKED' "$BMAD_MD"; then
  pass "instructs to stop on BLOCKED readiness verdict"
else
  fail "no BLOCKED handling found"
fi

# ---------------------------------------------------------------------------
# Negative: must not reimplement sub-command logic
# ---------------------------------------------------------------------------
if grep -qE '^## Step ' "$BMAD_MD"; then
  fail "bmad.md appears to reimplement sub-command logic ('## Step' sections found)"
else
  pass "bmad.md does not reimplement sub-command logic"
fi

# ---------------------------------------------------------------------------
# (opt) steps marked as optional
# ---------------------------------------------------------------------------
if grep -qE '\(opt\)' "$BMAD_MD"; then
  pass "(opt) steps are marked as optional"
else
  fail "no (opt) markers found for optional steps"
fi

# ---------------------------------------------------------------------------
# Journey diagram
# ---------------------------------------------------------------------------
if grep -q 'flowchart' "$JOURNEY_MMD" && grep -q 'subgraph' "$JOURNEY_MMD"; then
  pass "F27-journey.mmd is a flowchart with subgraphs (swimlanes)"
else
  fail "F27-journey.mmd missing flowchart/subgraph"
fi

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
