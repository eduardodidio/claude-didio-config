---
description: Plan a new feature (Architect only) — produces BMad-style tasks with Status=planned, no Waves executed
argument-hint: <FXX> <feature description>
---

You are running the **planning-only** pipeline of `claude-didio-config` for
project **{{PROJECT_NAME}}**.

The user asked to plan feature: **$ARGUMENTS**

## Your job

Run ONLY the Architect. Do **not** invoke Developer, TechLead, or QA. Do
**not** run any Wave. The output is a complete feature plan in BMad style
(User Story + Dev Notes + Testing per task), ready for later execution via
`/create-feature <FXX>`.

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
