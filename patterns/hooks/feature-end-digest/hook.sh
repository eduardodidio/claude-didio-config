#!/usr/bin/env bash
# type: hook
# tags: stop, digest, learning-loop
# Drops a learning digest file when a feature closes (Stop + QA report + Status: done).
# Fire-and-forget: uses set -u but NOT set -e. Always exits 0.

set -u

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$HOOK_DIR/../_lib/load-env.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOOK_DIR/../_lib/load-env.sh"
  load_hub_env
fi

if [ -f "$HOOK_DIR/../_lib/registry-match.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOOK_DIR/../_lib/registry-match.sh"
  if ! registry_match; then exit 0; fi
fi

if [ ! -f "$HOOK_DIR/../_lib/digest-context.sh" ]; then
  exit 0
fi
# shellcheck source=/dev/null
. "$HOOK_DIR/../_lib/digest-context.sh"

[ "${DIDIO_DIGEST_DISABLED:-0}" = "1" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROJECT_NAME="${CLAUDE_PROJECT_NAME:-$(basename "$PROJECT_DIR")}"

# Detect active feature: env var wins, then mtime fallback.
FEATURE="${DIDIO_FEATURE:-}"
if [ -z "$FEATURE" ]; then
  feat_dir="$(ls -dt "$PROJECT_DIR"/tasks/features/F[0-9]*-*/ 2>/dev/null | head -n1)"
  if [ -n "$feat_dir" ]; then
    FEATURE="$(basename "$feat_dir" | grep -oE '^F[0-9]+')"
  fi
fi
[ -n "$FEATURE" ] || exit 0

# Require a QA report created within the last 6 hours — confirms feature is closing now.
qa_report="$(find "$PROJECT_DIR/tasks/features/${FEATURE}"-* -maxdepth 1 \
  -name 'qa-report-*.md' -mmin -360 2>/dev/null | head -n1)"
[ -n "$qa_report" ] || exit 0

# Require Status: done in the feature README — confirms the feature shipped.
feature_readme="$(ls "$PROJECT_DIR"/tasks/features/"${FEATURE}"-*/"${FEATURE}"-README.md 2>/dev/null | head -n1)"
if [ -z "$feature_readme" ] || ! grep -q '^Status:[[:space:]]*done' "$feature_readme" 2>/dev/null; then
  exit 0
fi

# Compose drop path; idempotence: skip if this window already dropped.
drop_path="$PROJECT_DIR/memory/_pending-digest/${FEATURE}-$(date -u +%Y%m%dT%H%M%SZ).md"
[ -f "$drop_path" ] && exit 0

mkdir -p "$(dirname "$drop_path")"

emit_drop_payload "$FEATURE" "$PROJECT_NAME" "$PROJECT_DIR" > "$drop_path" || true
if [ ! -s "$drop_path" ]; then
  rm -f "$drop_path"
  exit 0
fi

exit 0
