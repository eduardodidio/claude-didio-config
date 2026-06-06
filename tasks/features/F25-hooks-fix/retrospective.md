# Retrospective — F25

## What worked

- Shell expansion convention (`${DIDIO_HOME:-$HOME/.claude-didio-config}`) applied consistently across template, sync guard, and downstream cleanup — one decision, portable everywhere.
- Placement of the placeholder guard inside the sync's per-hook loop (after dedup check, before append) was architecturally correct: it reuses the existing command-set idiom with minimal new state (`skipped_ph` counter).
- Integration test (9 assertions) covered all guard branches including dry-run, real merge, boundary (no pre-existing hooks block), and clean template — grounded AC4 verdict in reproducible evidence.
- TechLead caught B1/B2 (duplicate hooks in second-brain repos) before QA — reading the review first focused QA on verifying fixes rather than rediscovering known issues.

## What to avoid

- **"Resolve placeholder → real path" without pre-existing dedup check.** T04's inline script added resolved hooks without checking if the resolved value already existed in the destination. The sync guard's `existing_cmds` set is the correct model — any downstream cleanup task that translates `{{X}}` → value must collect existing commands first.
- **Named test harness in test plan with no existence check before approving.** `bin/tests/F25-unit.sh` was specified in F25-test-plan.md but never created by the developer. This is the 4th instance of this pattern across features (F09, F13, F15, F25). Missing → BLOCKING, not IMPORTANT.
- **Upstream files not committed before QA.** `templates/.claude/settings.json`, `.claude/settings.json`, and `bin/didio-sync-project.sh` were all modified but unstaged/uncommitted at the time of TechLead review. AC5 required upstream commit; QA had to commit them.

## Patterns to repeat

- For any "cleanup broken hooks" task targeting repos with non-standard pre-existing state: always `diff` before/after with `git diff HEAD` before committing. Catches silent regressions (duplicate entries) that JSON lint won't flag.
- TechLead `## Retrospective Seeds` section: directly actionable for QA triage. Read it before starting inspection — each seed is a pre-diagnosed issue with role assignment.
- Placeholder guard as a **sync-layer defense** (strip `{{` at merge time) is the right pattern for any config-templating pipeline where resolution happens at install time, not sync time.

## Propagated to learnings

- `memory/agent-learnings/developer.md` — resolve-placeholder dedup pattern + upstream commit before QA
- `memory/agent-learnings/techlead.md` — named harness existence check as BLOCKING gate
- `memory/agent-learnings/qa.md` — upstream commit verification + TechLead Retrospective Seeds as first read
