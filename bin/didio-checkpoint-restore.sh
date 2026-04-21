#!/usr/bin/env bash
# didio-checkpoint-restore.sh — validate a checkpoint JSON and print its
# next_action_hint.
#
# Usage: didio-checkpoint-restore.sh <checkpoint.json>
# Exit:  0 if valid + non-empty next_action_hint (printed to stdout)
#        1 otherwise

set -u
CKPT="${1:?checkpoint path required}"
[[ -f "$CKPT" ]] || exit 1

python3 - "$CKPT" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        c = json.load(f)
except Exception:
    sys.exit(1)
for k in ("run_id", "updated_at"):
    if k not in c:
        sys.exit(1)
hint = (c.get("next_action_hint") or "").strip()
if not hint:
    sys.exit(1)
print(hint)
PY
