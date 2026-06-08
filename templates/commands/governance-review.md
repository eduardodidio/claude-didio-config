---
description: Run Saruman governance review on a Gandalf decision
---

# /governance-review — Saruman Governance Review

You are executing an on-demand governance review of a Gandalf decision
using the Saruman meta-agent.

## Input

The user provides: `$ARGUMENTS` (optional decision-id, e.g. `D-20260605-001`)

## Pre-flight Checks

1. Read `didio.config.json` and check `meta_agents.t1000.enabled`.
   If `false` or missing, inform the user:
   > Saruman is disabled. To enable: set `meta_agents.t1000.enabled: true`
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
   - Ask user if they want to re-run Gandalf with the feedback
   - If yes, spawn Gandalf in re-evaluate mode

4. If verdict is **escalate**:
   - Clearly communicate that the pipeline is blocked
   - Show the specific concerns
   - Ask user for their decision on how to proceed

## Notes

- Saruman operates with restricted context (only reads decision records,
  CLAUDE.md, and didio.config.json) — this is intentional
- Use this for on-demand reviews of decisions that weren't auto-reviewed
- Governance reports persist in `logs/governance/` for audit trail
