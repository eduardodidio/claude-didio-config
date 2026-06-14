#!/usr/bin/env bash
# didio-compile-skills.sh — compile skills/*.md (neutral format) into
# provider-specific artifacts: .claude/commands, .claude/agents, agents/prompts
# for Claude; ~/.codex/prompts/*.md + AGENTS.md for Codex (subagent skills have
# no Codex analogue and are skipped with a logged note).
#
# Usage: didio-compile-skills.sh [--target claude|codex|all] [--dry-run]
#                                 [--skills-dir DIR] [--output-root DIR]
#                                 [--out-codex DIR]
#
# See skills/SPEC.md for the neutral skill format.
set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 "$SCRIPT_DIR/didio-compile-skills.py" "$@"
