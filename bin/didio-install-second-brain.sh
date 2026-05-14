#!/usr/bin/env bash
# didio-install-second-brain.sh — clone or update didio-second-brain-claude.
#
# Usage: didio-install-second-brain.sh [TARGET_DIR]
#
# Env:
#   DIDIO_SECOND_BRAIN_REPO_URL  Override repo URL.
#
# Exit codes:
#   0  success (cloned, updated, or already up-to-date)
#   1  git failure
#   2  target exists but is not a git checkout

set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<EOF
Usage: didio-install-second-brain.sh [TARGET_DIR]

Clone or update the didio-second-brain-claude MCP repo idempotently.

  TARGET_DIR  Where to clone (default: \$DIDIO_SECOND_BRAIN_HOME or
              \$HOME/didio-second-brain-claude)

Environment:
  DIDIO_SECOND_BRAIN_REPO_URL  Override repo URL.

Exit codes:
  0  success (cloned, updated, or already up-to-date)
  1  git failure
  2  target exists but is not a git checkout
EOF
    exit 0
    ;;
esac

REPO_URL="${DIDIO_SECOND_BRAIN_REPO_URL:-https://github.com/eduardodidio/didio-second-brain-claude.git}"
TARGET="${1:-${DIDIO_SECOND_BRAIN_HOME:-$HOME/didio-second-brain-claude}}"

# Normalize to absolute path
case "$TARGET" in
  /*) ;;
  *) TARGET="$PWD/$TARGET" ;;
esac

say()  { printf '\033[1;36m[didio-install-sb]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[didio-install-sb]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[didio-install-sb]\033[0m %s\n' "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required"

if [[ -d "$TARGET/.git" ]]; then
  say "updating existing checkout at $TARGET"
  git -C "$TARGET" pull --ff-only 2>&1 | sed 's/^/[git] /' >&2 \
    || warn "pull failed (local divergence?) — continuing with current state"
elif [[ -e "$TARGET" ]]; then
  printf '\033[1;31m[didio-install-sb]\033[0m %s\n' \
    "path $TARGET exists and is not a git checkout — move it aside and retry" >&2
  exit 2
else
  say "cloning $REPO_URL -> $TARGET"
  git clone "$REPO_URL" "$TARGET" 2>&1 | sed 's/^/[git] /' >&2 || die "clone failed"
fi

# Sanity check
if [[ ! -f "$TARGET/patterns/hooks/stop-session-summary/hook.sh" ]]; then
  warn "expected hook layout missing at $TARGET/patterns/hooks/ — upstream may have changed"
fi

# Print resolved path on stdout (callers capture this)
echo "$TARGET"
