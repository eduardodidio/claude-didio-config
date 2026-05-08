#!/usr/bin/env bash
# mock-claude.sh — stand-in for `claude -p` in F22 tests.
# Emits the JSONL referenced by MOCK_CLAUDE_FIXTURE and exits
# with MOCK_CLAUDE_EXIT (default 0).
set -euo pipefail
FIXTURE="${MOCK_CLAUDE_FIXTURE:?set MOCK_CLAUDE_FIXTURE to a basename in this dir}"
EXIT="${MOCK_CLAUDE_EXIT:-0}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE_PATH="$DIR/$FIXTURE"
[[ -f "$FIXTURE_PATH" ]] || { echo "mock-claude: fixture not found: $FIXTURE_PATH" >&2; exit 127; }
cat "$FIXTURE_PATH"
exit "$EXIT"
