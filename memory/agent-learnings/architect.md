# Architect Agent Learnings

## F06 — 2026-04-18

**What worked:** Wave structure mirrored the plan's logical phases (config, migration, prompt update + spawn, integration test + benchmark + docs, ADR) with explicit dependency arrows in the F06-README manifest. Wave 2 had 5 parallel-safe tasks (T04–T08 each editing different files) — paid off in execution speed without collisions.

**What to avoid:** Planning a refactor based on "the plan says cat X" without verifying the actual code path. The original plan referenced removing `cat memory/agent-learnings/` from the spawn script, but the injection was via a prompt instruction, not a `cat` in bash. Pivoted to "edit prompt templates + add sentinel substitution" — but the architect should have caught the mismatch in the planning phase by reading the spawn script directly.

**Pattern to repeat:** When planning any feature that touches `bin/didio-config-lib.sh`, include a task that flips `didio-spawn-agent.sh` to prefer project-local lib resolution (`PROJECT_ROOT/bin/didio-config-lib.sh`) over `${DIDIO_HOME}` if not already done. One-time change, compounds across every future feature that evolves the lib.

## F09 — 2026-04-25

**What worked:** Wave 0 as a blocking serial gate (scan-exclusion investigation + decision doc + scaffolding) was the right call — T03, T05, and the test file all depended on a binary Branch A/B decision. No rework because the dependency was explicit.

**What to avoid:** Writing user-facing eligibility docs that list criteria the script doesn't enforce. `archive/README.md` originally had 3 eligibility criteria; `has_passed_qa()` only checked 2. The third ("no planned tasks") was aspirational. Rule: every criterion in a user-facing eligibility doc must have a matching code check, or be marked explicitly as "(not yet enforced)". Aspirational criteria erode trust when users find the gate doesn't actually block.

**Pattern to repeat:** When a Wave-0 task produces a machine-readable decision line (read by downstream scripts via awk/grep), name it precisely: `## Decision` section with a first-non-empty line that is a valid case-match token (e.g., `gitignore-only`, `settings.json: <field>`). Document this contract in the Wave-0 task's "Dev Notes" so downstream tasks don't have to infer the format.

## F07 — 2026-04-20

**What worked:** Wave 0 front-loaded the schemas + config block + `DIDIO_RUN_ID` export before any hook could consume them. Zero stalls during subsequent waves because every downstream script found its contract already in place. Brief-as-task-zero pattern (the handwritten `_brief.md`) gave the Architect enough context to decompose cleanly without re-exploring.

**What to avoid:** Skipping the mandatory 2-diagram check. The Architect spec says "two diagrams per feature, non-negotiable" — F07 shipped without them and the TechLead caught the gap (had to create inline during review). Plan files should include a diagram subsection as a first-class deliverable, not an afterthought in a task's Dev Notes.

**Pattern to repeat:** When planning a feature that adds a gating hook (anything that can deny tool calls via matcher "*"), include a Wave 0 task for the staleness guard — not an optional feature, a mandatory defensive layer. Any on-disk state a hook reads needs a `max_age_secs` config with sensible default (300s here) and a mtime-based skip.
