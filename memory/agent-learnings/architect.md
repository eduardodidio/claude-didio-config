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

## F10 — 2026-04-26
**What worked:** Wave manifest with explicit serial gates (Wave 0 blocking, Wave 3 sequential) prevented dependency violations across 13 tasks. Report-spec as a shared contract between agent (writer) and slash command (parser) let both sides evolve independently without coordination.

**What to avoid:** Implicit file dependencies not captured in the Wave manifest. If task B's AC requires file X to exist, task A (the owner of X) must list X in "Files touched" AND the README dependency graph must include an explicit arrow A→B. Silent implicit dependencies become discovered-at-T10 surprises. Also: sanity/debug FORCE overrides (e.g. `DIDIO_READINESS_FORCE=1`) should be specced in the prompt task (Wave 1) when the Wave 3 task that needs them is already planned — not added retroactively to a `done` task.

**Pattern to repeat:** Add a Wave-completion pre-check before TechLead: every task from Wave 0–N should be `Status: done`; any exception must be explicitly flagged in the TechLead spawn call. This mirrors what the readiness gate does for plans — do the same for execution completeness.

## F11 — 2026-04-26
**What worked:** Explicit parallelism constraints in the wave manifest (T02-T05 touch distinct files, no overlap) prevented conflicts during parallel Wave 1 execution. Architecture-layer table (listing exactly which files each task touches) is the right artifact for complex multi-file features.

**What to avoid:** Under-constrained briefs for complex slash-command features — Architect ran 3 times (2 failures, 1 kill) on F11 before converging. For features that are "orchestration-only" (no code, only templates + slash commands), the brief should enumerate the exact files to create/edit and the expected diff at a high level. Vague briefs lead to planning cycles.

**Pattern to repeat:** For slash-command features: make the question template the single source of truth (not the command body) and cite it in the brief explicitly. This keeps the command body lean and the template independently editable — which the AC structure can then verify via negative grep.

## F12 — 2026-04-27

**What worked:** Sharding contract as a self-validating output — requiring each generated task to cite ≥1 shard in `## Dev Notes` lets structural smoke tests verify sharding correctness without a live model run. The opt-in threshold trio (`enabled`, `brief_lines_threshold`, `task_count_threshold`) is the right shape for Tier 2 features: small features pay zero overhead.

**What to avoid:** Omitting the kill-switch paths from the architecture diagram. All three gateways (sharding.enabled, brief_lines_threshold, task_count_threshold) must appear in the diagram — a reviewer who only reads the diagram should be able to understand every opt-out path.

**Pattern to repeat:** When introducing a sharded brief, write `_brief/00-overview.md` as the always-read summary and `NN-<component>.md` as component shards. Every generated task's `## Dev Notes` must cite the relevant shard(s). This is programmatically verifiable and prevents context bloat in Developer/QA agents that only need one component.

## F13 — 2026-04-27

**What worked:** Reusing F10 (check-readiness) as the structural template for TEA (same role registration pattern, same slash-command shape, same pipeline gate) reduced implementation scope significantly. Wave 1 parallelism with 4 tasks touching strictly disjoint files prevented conflicts.

**What to avoid:** Spec'ing a pre-Wave gate across two separate tasks (T06 for `create-feature`, T07 for `didio`) — the T06 developer added the gate only to `didio.md`. Both commands are pipeline entry points; gates must land atomically. When planning a multi-entry-point gate, make it a single task or add an explicit cross-task consistency requirement to both.

**Pattern to repeat:** Opt-in pre-Wave gate shape: `(config.enabled=false default) + (env-var bypass DIDIO_X_SKIP=1) + (forward-compat marker for coordinating sibling feature)`. This triple is portable to any future pre-Wave gate. New role registration must cover all 4 locations atomically: `didio-spawn-agent.sh`, `bin/didio`, `didio-sync-project.sh`, both config files.
