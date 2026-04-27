---
type: hook
projects: [all]
tags: [stop, digest, learning-loop]
updated: 2026-04-26
---

# feature-end-digest hook

Drops a structured learning digest into `memory/_pending-digest/` at the end
of a feature cycle. The drop is later ingested by the MCP tool
`memory.digest_pending` (or the cron script in `_bootstrap/scripts/`) without
any manual intervention.

## Trigger conditions (all three must be true)

1. **Stop event** — Claude Code session is ending.
2. **QA report recent** — a `qa-report-*.md` file exists under
   `tasks/features/<FXX>-*/` and was modified within the last 6 hours.
3. **Status: done** — `tasks/features/<FXX>-*/<FXX>-README.md` contains
   the line `Status: done`.

If any condition fails the hook exits 0 immediately without writing anything.
This prevents spurious drops from mid-session Stop events.

## Output

```
<project_root>/memory/_pending-digest/<FXX>-<YYYYMMDDTHHMMSSz>.md
```

The file follows the ADR-0010 drop schema (frontmatter + 4 markdown sections):
`Learnings`, `Skills`, `Patterns`, `Anomalies`.

## Kill switch

Set `DIDIO_DIGEST_DISABLED=1` in the environment (or `.env`) to disable the
hook entirely. Checked before any file I/O.

## Privacy / token redaction

Token patterns (`sk-*`, `ghp_*`, `xoxb-*`) are automatically redacted to
`[REDACTED-TOKEN]` by the `emit_drop_payload` helper in
`_lib/digest-context.sh` before the file is written.

## Idempotence

The drop filename includes a UTC timestamp at second resolution. If a file
with the same path already exists (e.g., the hook fires twice in the same
second), the hook exits 0 without overwriting.

## Dependencies

- `patterns/hooks/_lib/load-env.sh` — loads `.env` from hub root
- `patterns/hooks/_lib/registry-match.sh` — filters to registered projects
- `patterns/hooks/_lib/digest-context.sh` — `emit_drop_payload` and
  collection helpers

All three are sourced with a `[ -f ... ]` guard; their absence causes a
silent `exit 0`, never an error.

## Files

| File | Purpose |
|------|---------|
| `hook.sh` | Main hook script |
| `hook.json` | Claude Code hook configuration (Stop event, matcher `*`) |
| `README.md` | This file |
