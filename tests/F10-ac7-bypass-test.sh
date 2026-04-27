#!/usr/bin/env bash
# F10 AC7 — Structural verification that DIDIO_SKIP_READINESS=1 bypass is
# documented in all three expected files. Slash commands execute inside a
# Claude session and cannot be driven by shell, so the automated guarantee
# here is that the bypass text is present in every place it must be enforced.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

FAIL=0

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
check_text() {
  local file="$1" needle="$2" label="$3"
  if grep -qF "$needle" "$DIDIO_HOME/$file"; then
    echo "OK [$label]: '$needle' present in $file"
  else
    echo "FAIL [$label]: '$needle' NOT found in $file"
    FAIL=1
  fi
}

# ---------------------------------------------------------------------------
# AC7a — bypass token present in /check-readiness command
# ---------------------------------------------------------------------------
check_text ".claude/commands/check-readiness.md" \
  "DIDIO_SKIP_READINESS=1" "AC7a /check-readiness token"

check_text ".claude/commands/check-readiness.md" \
  "Bypass de emergência" "AC7a /check-readiness section header"

# ---------------------------------------------------------------------------
# AC7b — bypass guard present in /create-feature (Step 1.5)
# ---------------------------------------------------------------------------
check_text ".claude/commands/create-feature.md" \
  "DIDIO_SKIP_READINESS=1" "AC7b /create-feature token"

check_text ".claude/commands/create-feature.md" \
  "Step 1.5" "AC7b /create-feature step label"

# ---------------------------------------------------------------------------
# AC7c — bypass guard present in /didio option 1
# ---------------------------------------------------------------------------
check_text ".claude/commands/didio.md" \
  "DIDIO_SKIP_READINESS=1" "AC7c /didio token"

check_text ".claude/commands/didio.md" \
  "Fase 1.5" "AC7c /didio phase label"

# ---------------------------------------------------------------------------
# AC7d — template mirror consistency (live == template)
# ---------------------------------------------------------------------------
for cmd in check-readiness create-feature didio; do
  if diff -q \
    "$DIDIO_HOME/.claude/commands/${cmd}.md" \
    "$DIDIO_HOME/templates/.claude/commands/${cmd}.md" > /dev/null 2>&1; then
    echo "OK [AC7d]: .claude/commands/${cmd}.md identical to template"
  else
    echo "FAIL [AC7d]: .claude/commands/${cmd}.md DIFFERS from template"
    FAIL=1
  fi
done

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [[ $FAIL -eq 0 ]]; then
  echo ""
  echo "PASS — AC7 bypass documentation verified (9/9 checks)"
else
  echo ""
  echo "FAIL — AC7 bypass checks failed (see above)"
fi

[[ $FAIL -eq 0 ]]
