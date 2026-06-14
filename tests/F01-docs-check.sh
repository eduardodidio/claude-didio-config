#!/usr/bin/env bash
# F01-docs-check.sh — verify F01 ADRs/diagrams/docs deliverables.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/claude-didio-config}"
SHIP_REPO="/Users/eduardodidio/the-grey-havens-config"

fail=0

check_adr() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "FAIL: missing ADR file: $file"
    fail=1
    return
  fi
  for section in "## Context" "## Decision" "## Consequences"; do
    if ! grep -q "^${section}$" "$file"; then
      echo "FAIL: $file missing section '$section'"
      fail=1
    fi
  done
  if ! grep -qE '^\*\*Status:\*\* (proposed|accepted|deprecated|superseded)' "$file"; then
    echo "FAIL: $file missing valid Status field"
    fail=1
  fi
}

# Happy path: both ADRs exist with required sections + status, in both repos.
check_adr "$DIDIO_HOME/docs/adr/0004-multi-provider-driver-architecture.md"
check_adr "$DIDIO_HOME/docs/adr/0005-neutral-skill-compile-model.md"
check_adr "$SHIP_REPO/docs/adr/0002-multi-provider-driver-architecture.md"
check_adr "$SHIP_REPO/docs/adr/0003-neutral-skill-compile-model.md"

# Edge case: numbering is sequential and unique (no collision with 0001).
if [[ -f "$SHIP_REPO/docs/adr/0001-adopt-claude-didio-framework.md" ]]; then
  for n in 0002 0003; do
    count=$(find "$SHIP_REPO/docs/adr" -maxdepth 1 -name "${n}-*.md" | wc -l | tr -d ' ')
    if [[ "$count" -ne 1 ]]; then
      echo "FAIL: expected exactly one ADR numbered $n in $SHIP_REPO/docs/adr, found $count"
      fail=1
    fi
  done
fi

# Boundary values: non-goals explicitly list API-path / Python-rewrite / extra-providers.
provider_adr="$SHIP_REPO/docs/adr/0002-multi-provider-driver-architecture.md"
for phrase in "API-direct" "Python" "providers beyond Claude"; do
  if ! grep -q "$phrase" "$provider_adr"; then
    echo "FAIL: $provider_adr missing non-goal reference: '$phrase'"
    fail=1
  fi
done

# T17: README + CLAUDE.md multi-provider docs, in both repos.
for repo in "$DIDIO_HOME" "$SHIP_REPO"; do
  readme="$repo/README.md"
  if ! grep -q "^## Multi-provider (Claude + Codex)" "$readme"; then
    echo "FAIL: $readme missing 'Multi-provider (Claude + Codex)' section"
    fail=1
  fi
  for cmd in "compile-skills" "providers list" "providers validate"; do
    if ! grep -q -- "$cmd" "$readme"; then
      echo "FAIL: $readme missing reference to '$cmd'"
      fail=1
    fi
  done
  for phrase in "fallback" "Subagents" "n/a"; do
    if ! grep -q "$phrase" "$readme"; then
      echo "FAIL: $readme missing documented gap reference: '$phrase'"
      fail=1
    fi
  done

  claude_md="$repo/CLAUDE.md"
  if ! grep -qi "codex" "$claude_md"; then
    echo "FAIL: $claude_md missing multi-provider/Codex note"
    fail=1
  fi
done

# Guardrails section must remain intact in the shipping repo's CLAUDE.md.
if ! grep -q "^## Guardrails de Segurança$" "$SHIP_REPO/CLAUDE.md"; then
  echo "FAIL: $SHIP_REPO/CLAUDE.md missing 'Guardrails de Segurança' section"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "PASS: F01 docs check"
fi

exit "$fail"
