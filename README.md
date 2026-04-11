# claude-didio-config

Opinionated Claude Code framework for starting new projects with a consistent
ritual: `CLAUDE.md`, ADRs, PRDs, incremental diagrams, and a 4-agent workflow
(Architect → Developer → TechLead → QA) organized in parallel Waves.

## What it gives you

- **One-shot bootstrap** — run `/install-claude-didio-framework` inside any
  empty project and answer a few questions. You get docs, prompts, tasks, and
  `.claude/` config materialized from templates.
- **4-agent workflow** — Architect plans minimal tasks grouped in parallel
  Waves (Wave 0 reserved for permissions/setup). Developer implements,
  TechLead reviews, QA validates.
- **Clean-context agents** — each agent is launched in a *new bash process*
  via `claude -p` (headless). Zero context pollution between Waves. All output
  streamed to `logs/agents/*.jsonl`.
- **Native `/create-feature` command** — no more copy-pasting the long Waves
  prompt. The command encodes it once.
- **Highlander mode (opt-in)** — `.claude/settings.json` pre-configured with
  liberal `permissions.allow` so Waves run without approval prompts. Only for
  sandboxed projects.
- **Monitoring dashboard (phase 2)** — Vite+React dashboard that tails
  `logs/agents/*.jsonl` and shows Wave progress in the browser.

## Install

```bash
curl -sSL https://raw.githubusercontent.com/eduardodidio/claude-didio-config/main/install.sh | bash
```

The installer:

1. Clones this repo into `~/.claude-didio-config/`
2. Symlinks `~/.local/bin/didio` → `~/.claude-didio-config/bin/didio`
3. Prints next steps

## Bootstrap a new project

```bash
cd my-new-project
claude
> /install-claude-didio-framework
```

You will be asked:

1. **Project name**
2. **Project model** — `java-spring-react`, `node-react`, `python-fastapi`, `blank`
3. **Highlander mode** — auto-approve permissions for Waves (y/N)
4. **Create ADR-0001** documenting the framework adoption (Y/n)

## Run a feature

```bash
claude
> /create-feature F01 add hello-world endpoint with health check UI
```

This triggers Architect → Wave 0 (permissions) → Waves 1..N (Developer in
parallel) → TechLead → QA. Each step runs in a fresh bash via
`didio spawn-agent`, with logs in `logs/agents/`.

## Project layout after bootstrap

```
my-project/
├── CLAUDE.md
├── docs/
│   ├── adr/
│   ├── prd/
│   ├── diagrams/
│   └── README.md
├── tasks/
│   └── features/
├── agents/
│   ├── orchestrator.md
│   ├── workflows/feature-workflow.md
│   └── prompts/
├── logs/agents/          (gitignored)
└── .claude/
    ├── settings.json
    ├── commands/
    └── agents/
```

## Status

**Phase 1 (backbone):** install, spawn-agent, run-wave, templates, agent
prompts, slash commands, project models, Highlander mode.

**Phase 2 (dashboard):** Vite+React monitoring UI, log watcher, browser entry
via `didio dashboard`.
