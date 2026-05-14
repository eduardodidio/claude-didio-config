---
name: install-claude-didio-framework
description: Bootstrap a new project with the claude-didio-config framework (CLAUDE.md, guardrails, docs/, tasks/, agents/, memory/agent-learnings/, .claude/, diagram templates). Use whenever the user says anything like "Claude, install claude-didio-config", "Claude, instale o framework de github.com/eduardodidio/claude-didio-config", or runs /install-claude-didio-framework in an empty or newly-started project.
---

# Install claude-didio-config into this project

## Natural language triggers

If the user says any of the following (or equivalents), you should
invoke this skill:

- "Claude, install claude-didio-config"
- "Claude, instale o framework de github.com/eduardodidio/claude-didio-config"
- "Claude, set up the didio framework in this project"
- "/install-claude-didio-framework"

If `DIDIO_HOME` is not set or the repo isn't cloned, run
`install.sh` from GitHub first:

```bash
curl -sSL https://raw.githubusercontent.com/eduardodidio/claude-didio-config/main/install.sh | bash
```

Then proceed with the interactive bootstrap below.

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
   - Explain: "Highlander mode activates Claude Code Auto Mode
     (`permissions.defaultMode: \"auto\"`) and pre-approves a liberal
     allow-list as fallback so Waves run without prompting. It is the
     equivalent of turning Auto Mode on. Only use it in sandboxed
     projects without secrets."
4. **Create ADR-0001** documenting framework adoption? — `yes` (default) / `no`
5. **Habilitar second-brain MCP?** — single select:
   - `yes` (recomendado) — Prior Learnings via MCP. Economiza tokens
     reusando learnings entre projetos.
   - `no` — Usar somente arquivos locais em `memory/agent-learnings/`.
   Default: `yes`.

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
   - `{{DIDIO_HOME}}` → resolved absolute path of the framework install,
     i.e. `$DIDIO_HOME` (or `$HOME/.claude-didio-config` if unset). Applied
     to `./.claude/settings.json` (PreToolUse + PostToolUse didio hooks) so
     the materialized file is portable across machines.
     Example sed:
     ```bash
     DIDIO_HOME_RESOLVED="${DIDIO_HOME:-$HOME/.claude-didio-config}"
     sed -i.bak "s|{{DIDIO_HOME}}|$DIDIO_HOME_RESOLVED|g" .claude/settings.json
     rm -f .claude/settings.json.bak
     ```

4. **Highlander mode**: if the user said yes, overwrite
   `./.claude/settings.json` with the contents of
   `./.claude/settings.highlander.json`. Leave both files in place so the
   choice is reversible.

4.5. **Second-brain hook substitution**: based on the answer to question 5.

   **If user answered `no`**:

   - Strip the three hook entries whose `command` contains
     `{{DIDIO_SECOND_BRAIN_HOME}}` from `./.claude/settings.json` using
     `python3 -c` (do NOT use Edit/sed — the targets live in nested arrays):

     ```bash
     python3 - <<'PY'
     import json
     p = '.claude/settings.json'
     with open(p) as f: s = json.load(f)
     for key in ('Stop', 'SubagentStop', 'PostToolUse'):
         entries = s.get('hooks', {}).get(key, [])
         for entry in entries:
             entry['hooks'] = [
                 h for h in entry.get('hooks', [])
                 if '{{DIDIO_SECOND_BRAIN_HOME}}' not in h.get('command', '')
             ]
         s['hooks'][key] = [e for e in entries if e.get('hooks')]
         if not s['hooks'][key]:
             del s['hooks'][key]
     with open(p, 'w') as f:
         json.dump(s, f, indent=2)
         f.write('\n')
     PY
     ```

   - In `./didio.config.json`, set `second_brain.enabled = false`:

     ```bash
     python3 - <<'PY'
     import json
     p = 'didio.config.json'
     with open(p) as f: c = json.load(f)
     c.setdefault('second_brain', {})['enabled'] = False
     with open(p, 'w') as f:
         json.dump(c, f, indent=2)
         f.write('\n')
     PY
     ```

   **If user answered `yes`**:

   1. Resolve `DIDIO_SECOND_BRAIN_HOME` via the helper lib:

      ```bash
      RESOLVED=$(bash -c 'source "$DIDIO_HOME/bin/didio-config-lib.sh"; didio_second_brain_home')
      ```

   2. If `$RESOLVED` is empty, invoke the helper script to clone:

      ```bash
      RESOLVED=$("$DIDIO_HOME/bin/didio-install-second-brain.sh") || RESOLVED=""
      ```

      If the helper exits non-zero, ask the user whether to retry or
      fall through to the "no" branch above.

   3. Substitute the placeholder in `./.claude/settings.json`:

      ```bash
      sed -i.bak "s|{{DIDIO_SECOND_BRAIN_HOME}}|$RESOLVED|g" ./.claude/settings.json
      rm ./.claude/settings.json.bak
      ```

   4. In `./didio.config.json`, set `second_brain.home = "$RESOLVED"` and
      `second_brain.enabled = true`. Use `python3 -c` with double-quoted
      string so `$RESOLVED` expands via the shell:

      ```bash
      python3 -c "
      import json
      p = 'didio.config.json'
      with open(p) as f: c = json.load(f)
      c.setdefault('second_brain', {})['home'] = '$RESOLVED'
      c['second_brain']['enabled'] = True
      with open(p, 'w') as f:
          json.dump(c, f, indent=2)
          f.write('\n')
      "
      ```

   5. JSON-validity check (mandatory):

      ```bash
      python3 -c "import json; json.load(open('.claude/settings.json'))" \
        || { echo "ERROR: settings.json corrupted after substitution"; exit 1; }
      ```

5. **ADR-0001**: if the user said no, delete
   `./docs/adr/0001-adopt-claude-didio-framework.md`. Otherwise fill in
   `{{DATE}}`, `{{PROJECT_OWNER}}`, `{{PROJECT_NAME}}`.

6. **`.gitignore`**: append these lines if not already present:
   ```
   logs/agents/*.jsonl
   logs/agents/*.meta.json
   logs/agents/state.json
   ```

6.1. **Create `memory/agent-learnings/`** with an empty
   `.gitkeep` and one placeholder file per role so the prompts have
   something to read:
   ```
   memory/agent-learnings/architect.md
   memory/agent-learnings/developer.md
   memory/agent-learnings/techlead.md
   memory/agent-learnings/qa.md
   ```
   Each file starts with a single header:
   ```markdown
   # <Role> Learnings

   (QA appends to this file at the end of every feature retrospective.)
   ```

7. **Verify**: run `ls -la ./CLAUDE.md ./agents/prompts/ ./tasks/features/
   ./.claude/commands/create-feature.md` and confirm everything is in
   place. Then run the following checks and include their output in the
   final report — surface any failure loudly and do not silently continue:

   ```bash
   # Confirm no hardcoded author paths remain:
   grep -c '/Users/eduardodidio/' .claude/settings.json
   # Expect: 0
   ```

   ```bash
   # If user said "no" to second-brain, confirm hook entries were stripped:
   python3 -c "
   import json
   s = json.load(open('.claude/settings.json'))
   hooks = s.get('hooks', {})
   for k in ('Stop','SubagentStop','PostToolUse'):
       for e in hooks.get(k, []):
           for h in e.get('hooks', []):
               assert 'DIDIO_SECOND_BRAIN_HOME' not in h.get('command',''), f'leftover hook in {k}'
   print('ok')
   "
   ```

   Both checks must print their result in the final report so the user
   sees confirmation.

8. **Install the user-level slash commands** (optional, ask the user):
   symlink `./.claude/commands/create-feature.md` and `dashboard.md` from
   the project so the user can invoke `/create-feature` and `/dashboard`.

## Final report to the user

Print a short welcome with:

- What was created (tree listing, 1 level deep)
- Whether Highlander mode was enabled
- The menu command: `/didio` (inside Claude Code) or `didio menu` (in
  the terminal)
- **Getting-started menu** — show these 4 suggestions prominently:
  1. 🆕 **Criar minha primeira feature** —
     `Claude, leia CLAUDE.md e crie a feature F01: <descrição>`
  2. 🐛 **Corrigir um bug** —
     `Claude, temos um bug: <desc>. Crie uma feature curta de 1 Wave`
  3. 🖥️ **Abrir o Didio Agents Dash** — `didio dashboard`
  4. 📚 **Explorar os prompts prontos** — `/didio` → opção 8
- **Higiene de contexto** — lembre o usuário:
  > ⚠️ Antes de iniciar cada nova feature, rode `/clear` pra limpar
  > o contexto. Isso evita decisões ruins e queima de tokens.
- A reminder that `didio` must be on `PATH` and that each agent runs
  in a clean bash context (so logs live in `logs/agents/`).

Close with: "Pra voltar a este menu a qualquer momento, rode `/didio`
(dentro do Claude Code) ou `didio menu` (no terminal)."
