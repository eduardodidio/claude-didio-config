---
description: Run T-1000 governance review on a T-800 decision
---

# /governance-review — T-1000 Governance Review

You are executing an on-demand governance review of a T-800 decision
using the T-1000 meta-agent.

## Input

The user provides: `$ARGUMENTS` (optional decision-id, e.g. `D-20260605-001`)

## Pre-flight Checks

1. Read `didio.config.json` and check `meta_agents.t1000.enabled`.
   If `false` or missing, inform the user:
   > T-1000 is disabled. To enable: set `meta_agents.t1000.enabled: true`
   > in `didio.config.json`.

2. Ensure `logs/decisions/` and `logs/governance/` directories exist.

## Execution

### If decision-id is provided

Run via Bash:

```bash
didio t1000 --decision <decision-id>
```

### If no decision-id provided

1. List recent decisions:
   ```bash
   didio decisions --recent 5
   ```
2. Ask the user which decision to review using AskUserQuestion
3. Run the review on the selected decision

### After Review

1. Read the governance report from `logs/governance/G-<decision-id>.json`
2. Present the results:
   - Verdict (agree / challenge / escalate)
   - Bias check results (any detected biases)
   - Blind spots identified
   - Risks flagged
   - Recommendation
   - Confidence level

3. If verdict is **challenge**:
   - Ask user if they want to re-run T-800 with the feedback
   - If yes, spawn T-800 in re-evaluate mode

4. If verdict is **escalate**:
   - Clearly communicate that the pipeline is blocked
   - Show the specific concerns
   - Ask user for their decision on how to proceed

## Notes

- T-1000 operates with restricted context (only reads decision records,
  CLAUDE.md, and didio.config.json) — this is intentional
- Use this for on-demand reviews of decisions that weren't auto-reviewed
- Governance reports persist in `logs/governance/` for audit trail
