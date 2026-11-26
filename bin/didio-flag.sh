#!/usr/bin/env bash
# didio-flag.sh — CLI wrapper for didio-flags-lib.sh
#
# Usage:
#   didio flag raise <feature> <type> [task] [message]
#   didio flag resolve <feature> <type> [task]
#   didio flag list [--feature FXX] [--unresolved]
#   didio flag is-blocked <feature> [task]
#
# Examples:
#   didio flag raise F30 blocked T01 "merge conflict in bin/didio"
#   didio flag resolve F30 blocked T01
#   didio flag list --feature F30 --unresolved
#   didio flag is-blocked F30

set -euo pipefail

DIDIO_HOME="${DIDIO_HOME:-$HOME/.claude-didio-config}"

# Source the flags library
FLAGS_LIB="${DIDIO_HOME}/bin/didio-flags-lib.sh"
if [[ -f "$PWD/bin/didio-flags-lib.sh" ]]; then
  FLAGS_LIB="$PWD/bin/didio-flags-lib.sh"
fi

if [[ ! -f "$FLAGS_LIB" ]]; then
  echo "[didio-flag] flags library not found: $FLAGS_LIB" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$FLAGS_LIB"

# --help
if [[ "${1:-}" = "--help" || "${1:-}" = "-h" ]]; then
  cat <<'EOF'
USAGE:
  didio flag raise <feature> <type> [task] [message]
      Raise a flag. Types: blocked, needs_review, warning, info, escalated
      Prints the flag filename on success.

  didio flag resolve <feature> <type> [task]
      Resolve all matching unresolved flags.
      Prints count of resolved flags.

  didio flag list [--feature FXX] [--unresolved]
      List flags. Without options lists all active (unresolved) flags.
      --feature FXX    Filter by feature ID
      --unresolved     Show only unresolved flags (default behavior)

  didio flag is-blocked <feature> [task]
      Check if a feature/task is blocked by an unresolved "blocked" flag.
      Prints "true" or "false". Exit 0 if blocked, 1 if not.

EXAMPLES:
  didio flag raise F30 blocked T01 "tests failing after merge"
  didio flag resolve F30 blocked T01
  didio flag list --feature F30
  didio flag is-blocked F30
EOF
  exit 0
fi

SUBCMD="${1:-}"
shift || true

case "$SUBCMD" in
  raise)
    if [[ $# -lt 2 ]]; then
      echo "Usage: didio flag raise <feature> <type> [task] [message]" >&2
      exit 1
    fi
    didio_flag_raise "$@"
    ;;
  resolve)
    if [[ $# -lt 2 ]]; then
      echo "Usage: didio flag resolve <feature> <type> [task]" >&2
      exit 1
    fi
    didio_flag_resolve "$@"
    ;;
  list)
    # Parse options
    LIST_FEATURE=""
    LIST_UNRESOLVED=1  # default: only unresolved
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --feature)
          LIST_FEATURE="${2:?--feature requires a value}"
          shift 2
          ;;
        --feature=*)
          LIST_FEATURE="${1#--feature=}"
          shift
          ;;
        --unresolved)
          LIST_UNRESOLVED=1
          shift
          ;;
        --all)
          LIST_UNRESOLVED=0
          shift
          ;;
        *)
          echo "Unknown option: $1" >&2
          exit 1
          ;;
      esac
    done

    FLAGS_DIR="$(_didio_flags_dir)"
    if [[ ! -d "$FLAGS_DIR" ]]; then
      echo "No flags directory found." >&2
      exit 0
    fi

    COUNT=0
    for flag_file in "$FLAGS_DIR"/*.json; do
      [[ -f "$flag_file" ]] || continue

      # Filter by resolved status
      if [[ "$LIST_UNRESOLVED" -eq 1 ]]; then
        resolved=$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('resolved_at') or '')
" "$flag_file" 2>/dev/null || echo "")
        [[ -n "$resolved" ]] && continue
      fi

      # Filter by feature
      if [[ -n "$LIST_FEATURE" ]]; then
        f_feature=$(python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(d.get('feature', ''))
" "$flag_file" 2>/dev/null || echo "")
        [[ "$f_feature" != "$LIST_FEATURE" ]] && continue
      fi

      # Print the flag as compact JSON
      python3 -c "
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    d = json.load(f)
print(json.dumps(d, separators=(',', ':')))
" "$flag_file" 2>/dev/null || continue
      COUNT=$((COUNT + 1))
    done

    if [[ $COUNT -eq 0 ]]; then
      echo "No flags found." >&2
    fi
    ;;
  is-blocked)
    if [[ $# -lt 1 ]]; then
      echo "Usage: didio flag is-blocked <feature> [task]" >&2
      exit 1
    fi
    didio_flag_is_blocked "$@"
    ;;
  ""|--help|-h)
    exec "$0" --help
    ;;
  *)
    echo "didio flag: unknown subcommand '$SUBCMD'. Try 'didio flag --help'." >&2
    exit 1
    ;;
esac
