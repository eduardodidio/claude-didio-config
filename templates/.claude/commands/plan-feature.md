---
description: Plan a new feature (Architect only) — produces BMad-style tasks with Status=planned, no Waves executed
argument-hint: <FXX> <feature description>
---

<!-- GENERATED FILE — DO NOT EDIT.
     Source: skills/plan-feature.md
     Regenerate with: didio compile-skills
-->

You are running the **planning-only** pipeline of `claude-didio-config` for
project **{{PROJECT_NAME}}**.

The user asked to plan feature: **$ARGUMENTS**

## Your job

Run ONLY the Architect. Do **not** invoke Developer, TechLead, or QA. Do
**not** run any Wave. The output is a complete feature plan in BMad style
(User Story + Dev Notes + Testing per task), ready for later execution via
`/create-feature <FXX>`.

## Step 0 — Gandalf Strategic Gate (conditional)

Before any agent runs, check if the Gandalf strategic orchestrator is enabled:

```bash
T800_ENABLED=$(python3 -c "import json; c=json.load(open('didio.config.json')); print(c.get('meta_agents',{}).get('t800',{}).get('enabled', False))" 2>/dev/null || echo "False")
```

If `T800_ENABLED` is `False` (default): **skip this step silently** and proceed to Step 1.

If `True`:
1. Write a decision request file to `logs/decisions/_requests/<FXX>-<timestamp>.md`:
   ```markdown
   # Decision Request: <FXX>
   **Type:** feature_start
   **Feature:** <description from $ARGUMENTS>
   **Requested at:** <ISO timestamp>
   **Pipeline:** plan-feature (Architect only, PLAN_ONLY mode)
   ```

2. Run:
   ```bash
   didio t800 <FXX> logs/decisions/_requests/<FXX>-<timestamp>.md
   ```

3. Find the latest decision record in `logs/decisions/D-*.json`.

4. Read its `status` field:
   - If `escalated`: **STOP the pipeline.** Print:
     > Gandalf/Saruman escalated this decision. Human review required.
     > Decision: logs/decisions/<id>.json
     > Governance: logs/governance/G-<id>.json
   - If `executed` or `reviewed` with governance verdict `agree`: **proceed** to Step 1.
   - If governance verdict `challenge` was resolved: **proceed** to Step 1.

5. Read the `actions` array. If the Gandalf recommends a different action
   than `plan-feature` or `create-feature` (e.g. `skip`, `research`),
   **STOP** and inform the user:
   > Gandalf recommends: <action> instead of plan-feature.
   > Rationale: <rationale from decision record>
   > Run the recommended command or override with DIDIO_SKIP_T800=1.

**Bypass:** if `DIDIO_SKIP_T800=1` is set, skip with a visible yellow warning:
> Warning: Gandalf gate bypassed via DIDIO_SKIP_T800=1

## Step 1 — Architect (PLAN_ONLY)

Extract the feature ID (e.g. `F07`) and description from `$ARGUMENTS`. If
the user did not supply an ID, pick the next free `F<NN>` by looking at
`tasks/features/`.

Write the feature brief to `tasks/features/<FXX>-_tmp-brief.md`, then run:

```bash
DIDIO_PLAN_ONLY=true didio spawn-agent architect <FXX> tasks/features/<FXX>-_tmp-brief.md
```

Wait for it to finish. Verify:

- `tasks/features/<FXX>-*/<FXX>-README.md` exists with `**Status:** planned`
- Each `<FXX>-TYY.md` has User Story, Dev Notes, Testing sections
- The final line is `DIDIO_DONE: architect planned ... (PLAN_ONLY mode) ...`

Delete the `_tmp-brief.md`.

## Step 2 — Final report

Summarize to the user:

- Feature ID + slug
- Number of tasks planned + number of waves
- Path: `tasks/features/<FXX>-<slug>/`
- Next step: run `/create-feature <FXX>` (or menu option 1) to execute the
  plan through Developer → TechLead → QA
- Link: `didio dashboard` for visual audit

## Rules

- NEVER run Developer/TechLead/QA in this flow.
- NEVER run `didio run-wave` in this flow.
- ALWAYS set `DIDIO_PLAN_ONLY=true` when spawning the Architect here.
- NEVER skip the Gandalf gate silently when enabled. The only valid bypass
  is `DIDIO_SKIP_T800=1` set explicitly by the user, with a visible warning.
