#!/usr/bin/env bash
# didio-notify.sh — best-effort user notification.
#
# Strategy (first that works, stop):
#   1. macOS: /usr/bin/osascript "display notification"
#   2. linux: notify-send if present
#   3. always: append to logs/notifications.log
#
# Returns 0 unconditionally — notifications are never fatal.

set -u
MSG="${1:-didio}"
PROJECT="${DIDIO_PROJECT_ROOT:-$(pwd)}"
LOG="$PROJECT/logs/notifications.log"
mkdir -p "$(dirname "$LOG")"
printf '%s  %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MSG" >> "$LOG" 2>/dev/null || true

case "$(uname -s)" in
  Darwin)
    /usr/bin/osascript -e "display notification \"${MSG//\"/\\\"}\" with title \"didio\"" >/dev/null 2>&1 || true
    ;;
  Linux)
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "didio" "$MSG" || true
    fi
    ;;
esac
exit 0
