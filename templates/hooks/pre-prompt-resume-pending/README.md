---
id: pre-prompt-resume-pending
name: F22 — Auto Resume Pending Rate-Limited Jobs
type: hook
event: SessionStart
status: opt-in
feature: F22
---

# F22 Hook — auto-resume on session start

Runs `didio resume-pending` whenever a Claude Code session starts.
Idempotent: skips jobs whose reset is in the future.

## Install (opt-in)

```bash
# Manual:
cp -r templates/hooks/pre-prompt-resume-pending \
      /path/to/your/project/patterns/hooks/

# Then merge hook.json into .claude/settings.json under "hooks":
#   "SessionStart": [ ... see hook.json ... ]
```

Or with the framework-managed sync (when added):
`didio sync-project /path/to/your/project --hook pre-prompt-resume-pending`.

## Behavior

- Reads `<project-root>/logs/agents/_pending/`.
- For each `<id>.json` whose `reset_at_unix` ≤ now: acquires lock,
  atomically consumes file, re-spawns the original `didio
  spawn-agent` invocation. See `bin/didio-resume-pending.sh`.

## Disable

Remove the entry under `SessionStart` in `.claude/settings.json`.

## Notes

- Errors are swallowed; the hook never blocks the session.
- Set `DIDIO_HOOKS_DISABLE_FILTER=1` if you run inside a project
  not present in `projects/registry.yaml` (e.g., the hub repo
  itself during development).
