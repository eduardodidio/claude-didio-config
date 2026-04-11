# Agent Orchestrator — {{PROJECT_NAME}}

Coordinates the 4 agents (Architect → Developer → TechLead → QA) for the
claude-didio-config framework.

## Core principle

**Every agent runs in a new, clean bash process via `didio spawn-agent`.**
No agent inherits the context of the orchestrator. This is intentional:
each role reads *only* the task file and the project state, which makes
their output reproducible and auditable (via `logs/agents/*.jsonl`).

## Flow

```
/create-feature "<description>"
  ↓
1. Architect   — didio spawn-agent architect <FXX> <feature-description>
                 Produces tasks/features/<FXX>-*/ with Waves manifest
  ↓
2. Wave 0      — didio run-wave <FXX> 0 developer
                 Setup, permissions, scaffolding (front-loaded)
  ↓
3. Waves 1..N  — didio run-wave <FXX> <N> developer     (in order; within each Wave, tasks in parallel)
  ↓
4. Tech Lead   — didio spawn-agent techlead <FXX> tasks/features/<FXX>-*/<FXX>-README.md
  ↓
5. QA          — didio spawn-agent qa <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

## Mandates

- **Testing** — every Wave ends only when the stack's test command passes
- **Diagrams** — every feature ends with diagrams in sync with code
- **Logs** — every agent invocation leaves a `logs/agents/*.jsonl` + `*.meta.json`
- **Clean context** — never reuse an agent across tasks; always spawn anew
