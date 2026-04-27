#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TARGET="${1:-/Users/eduardodidio/mellon-magic-maker}"
[[ -d "$TARGET" ]] || { echo "SKIP: target $TARGET missing"; exit 0; }

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

./bin/didio-sync-project.sh --dry-run "$TARGET" > "$OUT" 2>&1 || {
  echo "FAIL: sync dry-run errored"; cat "$OUT"; exit 1;
}

# Strip ANSI escape codes for clean grep
PLAIN=$(sed 's/\x1b\[[0-9;]*m//g' "$OUT")

# F15 does not add new sync steps to the sync pipeline (only bin/ files changed).
# Regression check: any ADDED entry for a non-template bin/ path would indicate
# an unintended scope expansion introduced by F15.
# bin/didio-archive-feature.sh is the only expected bin/ ADDED entry (pre-F15, from F09).
ALLOWED_BIN='bin/didio-archive-feature\.sh'

UNEXPECTED_BIN=$(echo "$PLAIN" | grep -E '^\s+\[ADDED\].*\bbin/' \
  | grep -vE "$ALLOWED_BIN" || true)

if [[ -n "$UNEXPECTED_BIN" ]]; then
  echo "FAIL: unexpected bin/ sync candidates (F15 should not expand sync scope):"
  echo "$UNEXPECTED_BIN"
  exit 1
fi

echo "PASS: sync dry-run scoped correctly — no unexpected bin/ additions from F15"
