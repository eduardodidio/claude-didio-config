#!/usr/bin/env bash
# didio-poc-from-minutes.sh — meeting-to-POC pipeline CLI entry.
#
# Usage:
#   didio-poc-from-minutes.sh <path-da-ata> [--name <slug>]
#                             [--dest <dir>] [--style-ref <path>]
#                             [--no-smoke] [--stop-after <step>]
#
# Steps: parse | scaffold | mock_gen | ui_gen | style | install_smoke | git
#
# Exit codes (forwarded from pipeline):
#   0 ok | 2 usage | 3 ata missing | 4 manifest invalid
#   5 npm install fail | 6 smoke fail | 7 git fail

set -euo pipefail

ATA="${1:?path-da-ata required}"
shift

NAME=""; DEST=""; STYLE_REF=""; NO_SMOKE=""; STOP_AFTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        NAME="$2";        shift 2 ;;
    --dest)        DEST="$2";        shift 2 ;;
    --style-ref)   STYLE_REF="$2";   shift 2 ;;
    --no-smoke)    NO_SMOKE="1";     shift   ;;
    --stop-after)  STOP_AFTER="$2";  shift 2 ;;
    -h|--help)     sed -n '2,15p' "$0" >&2; exit 0 ;;
    *)             echo "[didio-poc] unknown arg: $1" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(pwd)"
PIPELINE="$PROJECT_ROOT/bin/didio-poc-pipeline.py"

if [[ ! -f "$PIPELINE" ]]; then
  echo "[didio-poc] pipeline not found: $PIPELINE" >&2
  echo "[didio-poc] is this a claude-didio-config project?" >&2
  exit 2
fi

exec python3 "$PIPELINE" \
  --ata "$ATA" \
  ${NAME:+--name "$NAME"} \
  ${DEST:+--dest "$DEST"} \
  ${STYLE_REF:+--style-ref "$STYLE_REF"} \
  ${NO_SMOKE:+--no-smoke} \
  ${STOP_AFTER:+--stop-after "$STOP_AFTER"}
