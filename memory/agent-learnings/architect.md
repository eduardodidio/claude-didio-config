# Architect Agent Learnings

## F06 — 2026-04-18

**What worked:** Wave structure mirrored the plan's logical phases (config, migration, prompt update + spawn, integration test + benchmark + docs, ADR) with explicit dependency arrows in the F06-README manifest. Wave 2 had 5 parallel-safe tasks (T04–T08 each editing different files) — paid off in execution speed without collisions.

**What to avoid:** Planning a refactor based on "the plan says cat X" without verifying the actual code path. The original plan referenced removing `cat memory/agent-learnings/` from the spawn script, but the injection was via a prompt instruction, not a `cat` in bash. Pivoted to "edit prompt templates + add sentinel substitution" — but the architect should have caught the mismatch in the planning phase by reading the spawn script directly.

**Pattern to repeat:** When planning any feature that touches `bin/didio-config-lib.sh`, include a task that flips `didio-spawn-agent.sh` to prefer project-local lib resolution (`PROJECT_ROOT/bin/didio-config-lib.sh`) over `${DIDIO_HOME}` if not already done. One-time change, compounds across every future feature that evolves the lib.
