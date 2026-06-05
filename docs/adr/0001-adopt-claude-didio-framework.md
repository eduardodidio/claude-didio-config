# ADR-0001: Adopt claude-didio-config framework

**Status:** accepted
**Date:** {{DATE}}
**Deciders:** {{PROJECT_OWNER}}

## Context

We want a consistent project-start ritual across all new projects: a
`CLAUDE.md` entry point, ADRs, PRDs, incremental diagrams, a `tasks/features/`
structure, and a 4-agent Waves workflow (Architect → Developer → TechLead → QA).
Doing this by hand in every project is error-prone and slow.

## Decision

Adopt [claude-didio-config](https://github.com/eduardodidio/claude-didio-config)
as the canonical project bootstrap and agent orchestration framework for
{{PROJECT_NAME}}.

- Bootstrap via `/install-claude-didio-framework` (one-shot install).
- All agents run in **clean bash contexts** via `didio spawn-agent`.
- Features are triggered via `/create-feature` which runs
  Architect → Wave 0 → Waves 1..N (parallel) → TechLead → QA automatically.
- Agent outputs are logged to `logs/agents/*.jsonl` for audit and dashboard.

## Consequences

**Easier:**
- New features follow the same ritual without re-explaining the Waves prompt
- Agent runs are auditable (logs + meta.json per run)
- Parallel Waves use cores effectively
- Context pollution between agents is eliminated by design

**Harder:**
- Each agent spawn pays the `claude -p` cold-start cost
- Framework updates must be pulled from upstream manually (no auto-update yet)

## Alternatives considered

- **Ad-hoc prompts** — what we did before. Works but drifts between projects
  and requires copy-pasting the Waves prompt every time.
- **Native Claude Code subagents (`Agent` tool)** — isolates context within
  the current session but makes dashboard/logs harder and does not give
  true parallelism across shells.
