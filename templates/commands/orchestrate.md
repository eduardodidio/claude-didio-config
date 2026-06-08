---
description: Orchestrate a strategic decision via Gandalf meta-agent (with optional Saruman governance)
---

# /orchestrate — Strategic Decision via Gandalf

You are executing a strategic orchestration session using the Gandalf and
Saruman meta-agents.

## Input

The user provides: `$ARGUMENTS` (expected format: `<FXX> <description>`)

Parse the arguments:
- First token: feature ID (e.g. `F25`)
- Remaining tokens: decision context / feature description

## Pre-flight Checks

1. Read `didio.config.json` and check `meta_agents.t800.enabled`.
   If `false` or missing, inform the user:
   > Gandalf is disabled. To enable: set `meta_agents.t800.enabled: true`
   > in `didio.config.json`. This is opt-in to avoid unexpected token costs.

2. Ensure `logs/decisions/` directory exists (create if needed).

## Execution

### Phase 1 — Create Decision Request

Write a decision request file to `logs/decisions/_requests/<FXX>-<timestamp>.md`:

```markdown
# Decision Request: <FXX>

**Feature:** <description from user>
**Requested at:** <ISO timestamp>
**Current state:** <read from logs/agents/state.json if available>

## Context

<Summarize what you know about this feature — check if tasks/features/<FXX>-*/
exists, if there are planned tasks, recent decisions, etc.>

## Question

What is the best approach to proceed with <FXX>?
```

### Phase 2 — Spawn Gandalf

Run via Bash:

```bash
didio t800 <FXX> <request-file-path>
```

This spawns the Gandalf agent which produces a decision record in
`logs/decisions/D-YYYYMMDD-NNN.json`.

### Phase 3 — Report Results

After Gandalf completes:
1. Read the decision record from `logs/decisions/`
2. If auto_governance ran, read the governance report from `logs/governance/`
3. Present a summary to the user:
   - Decision type and selected option
   - Rationale
   - Planned actions
   - Governance verdict (if applicable)
   - Any escalations or challenges

### Phase 4 — Execute (with user confirmation)

If the decision was approved (not escalated):
- List the actions from the decision record
- Ask the user for confirmation before executing each action
- Execute approved actions using the appropriate didio commands
  (e.g. `/create-feature`, `didio run-wave`, etc.)

## Notes

- The Gandalf adds latency (~2-4 min) but provides structured decision-making
- For simple, obvious decisions, the user may prefer `/create-feature` directly
- Decision records serve as an audit trail in `logs/decisions/`
