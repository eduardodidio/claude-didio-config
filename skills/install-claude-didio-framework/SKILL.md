---
name: install-claude-didio-framework
description: Bootstrap a new project with the claude-didio-config framework (CLAUDE.md, ADRs, PRDs, diagrams, tasks/, agents/, .claude/). Use when the user runs /install-claude-didio-framework in an empty or newly-started project.
---

# Install claude-didio-config into this project

You are running the interactive bootstrap for the `claude-didio-config`
framework. Your job is to materialize all templates from
`$DIDIO_HOME/templates/` (default `~/.claude-didio-config/templates/`) into
the **current working directory**, substituting placeholders with answers
the user gives you.

## Preconditions

1. Verify `DIDIO_HOME` resolves (default `~/.claude-didio-config`) and
   contains `templates/`. If not, tell the user to run `install.sh` first.
2. Verify the current directory does NOT already contain `CLAUDE.md`,
   `agents/`, or `tasks/features/`. If any exist, ask the user whether to
   overwrite (default: abort).
3. Verify `didio` is on `PATH`. If not, suggest
   `export PATH="$PATH:$HOME/.local/bin"`.

## Interactive questions

Use the **AskUserQuestion** tool with these questions (one batch is fine):

1. **Project name** — free text (used in `CLAUDE.md`, ADR-0001)
2. **Project model** — single select:
   - `java-spring-react` (Java Spring Boot + React)
   - `node-react` (Node + React TypeScript fullstack)
   - `python-fastapi` (Python FastAPI)
   - `blank` (no predefined stack)
3. **Highlander mode** — single select: `no` (default) / `yes`
   - Explain: "Highlander mode pre-approves a liberal set of permissions so
     Waves run without prompting. Only use it in sandboxed projects without
     secrets."
4. **Create ADR-0001** documenting framework adoption? — `yes` (default) / `no`

## Materialization steps

After getting answers, do ALL of the following in order. Use shell `cp -r`
and `sed` for substitution, or Write/Edit tools as appropriate.

1. **Load the project model YAML** from
   `$DIDIO_HOME/project-models/<model>.yaml`. Extract `commands.build`,
   `commands.test`, `commands.run`, and `architecture_notes` — you'll plug
   these into `CLAUDE.md`.

2. **Copy the templates tree** from `$DIDIO_HOME/templates/` to `.`,
   preserving structure. Specifically:
   - `templates/CLAUDE.md.tmpl` → `./CLAUDE.md` (with placeholders filled)
   - `templates/docs/` → `./docs/`
   - `templates/tasks/` → `./tasks/`  (keep `FXX-template/` as reference)
   - `templates/agents/` → `./agents/`
   - `templates/.claude/` → `./.claude/`
   - `templates/logs/agents/.gitkeep` → `./logs/agents/.gitkeep`

3. **Substitute placeholders** in every copied file:
   - `{{PROJECT_NAME}}` → project name
   - `{{STACK}}` → model label (e.g. "Java Spring Boot + React")
   - `{{PROJECT_MISSION}}` → ask the user for a 1-sentence mission, or use
     a sensible default like "TBD — fill in after kickoff".
   - `{{STACK_ARCHITECTURE}}` → `architecture_notes` from the model YAML
   - `{{BUILD_CMD}}` / `{{TEST_CMD}}` / `{{RUN_CMD}}` → from model YAML
   - `{{DATE}}` → today's date (YYYY-MM-DD)
   - `{{PROJECT_OWNER}}` → the current git user.name (fallback to "TBD")
   - `{{EXTRA_PROJECT_NOTES}}` → empty

4. **Highlander mode**: if the user said yes, overwrite
   `./.claude/settings.json` with the contents of
   `./.claude/settings.highlander.json`. Leave both files in place so the
   choice is reversible.

5. **ADR-0001**: if the user said no, delete
   `./docs/adr/0001-adopt-claude-didio-framework.md`. Otherwise fill in
   `{{DATE}}`, `{{PROJECT_OWNER}}`, `{{PROJECT_NAME}}`.

6. **`.gitignore`**: append these lines if not already present:
   ```
   logs/agents/*.jsonl
   logs/agents/*.meta.json
   logs/agents/state.json
   ```

7. **Verify**: run `ls -la ./CLAUDE.md ./agents/prompts/ ./tasks/features/
   ./.claude/commands/create-feature.md` and confirm everything is in
   place.

8. **Install the user-level slash commands** (optional, ask the user):
   symlink `./.claude/commands/create-feature.md` and `dashboard.md` from
   the project so the user can invoke `/create-feature` and `/dashboard`.

## Final report to the user

Print:

- What was created (tree listing, 1 level deep)
- Whether Highlander mode was enabled
- The exact command to trigger the first feature:
  `/create-feature F01 <your first feature description>`
- A reminder that `didio` must be on `PATH` and that each agent runs in a
  clean bash context (so logs live in `logs/agents/`).
