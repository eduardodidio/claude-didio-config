---
description: Run the full Architect → Waves → TechLead → QA pipeline for a new feature
argument-hint: <FXX> <feature description>
---

You are orchestrating the claude-didio-config 4-agent Waves workflow for
project **{{PROJECT_NAME}}**.

The user asked for feature: **$ARGUMENTS**

## Your job (non-negotiable pipeline)

For each feature you execute EXACTLY this pipeline. Do not improvise.

1. **Architect** plans minimal tasks grouped in parallel Waves.
2. **Wave 0 includes ALL permissions, scaffolding, and dependencies** the
   later Waves need, so Waves 1..N run without interruption.
3. **Developer** implements each task.
4. **TechLead** reviews all tasks.
5. **QA** validates end-to-end and fills test gaps.

Constraints:
- Tasks must be **as small as possible** while still self-contained.
- Waves are **independent** — tasks in the same Wave must not touch each
  other's files.
- **Backend and frontend in the same Wave** whenever they don't share files.
- Every agent runs in a **clean bash context** via `didio spawn-agent` — you
  do NOT use the Agent tool for these; you shell out to `didio`.

## Step 1 — Architect

Extract the feature ID (e.g. `F07`) and description from `$ARGUMENTS`.
If the user did not supply an ID, pick the next free `F<NN>` by looking at
`tasks/features/`.

Write the feature brief to a temporary file
`tasks/features/<FXX>-_tmp-brief.md` containing just the feature description,
then run:

```bash
didio spawn-agent architect <FXX> tasks/features/<FXX>-_tmp-brief.md
```

Wait for it to finish. Verify `tasks/features/<FXX>-*/<FXX>-README.md` now
exists and contains a `Wave N:` manifest. Delete the `_tmp-brief.md`.

## Step 1.5 — Readiness gate (pre-Wave audit)

Before firing Wave 0, run the readiness audit. The agent reads
`<FXX>-README.md` + every `<FXX>-T*.md` and produces
`tasks/features/<FXX>-*/readiness-report.md` with a binary verdict.

```bash
/check-readiness <FXX>
```

(Equivalente em bash, se preferir invocar diretamente:
`didio spawn-agent readiness <FXX> tasks/features/<FXX>-*/<FXX>-README.md`,
seguido de `grep -E '^\*\*Verdict:\*\* BLOCKED' tasks/features/<FXX>-*/readiness-report.md`
para detectar BLOCKED.)

If the slash command exits 1 (verdict `BLOCKED`):
- STOP the pipeline.
- Print the path of `readiness-report.md` to the user.
- Tell the user to fix the plan and re-run `/create-feature <FXX>`.

If the user **explicitly** sets `DIDIO_SKIP_READINESS=1` in the environment,
skip this step (with a yellow warning) and proceed straight to Step 2.
**Never** skip silently.

## Step 1.7 — TEA gate (test architect, opt-in)

If `didio.config.json:tea.enabled` is `true` AND `DIDIO_SKIP_TEA` is not set,
spawn the TEA agent to write `<FXX>-test-plan.md`:

```bash
didio spawn-agent tea <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

Verify the file was created with all 7 sections per `docs/F13-test-plan-spec.md`.
If `tea.enabled` is `false`, skip silently (TEA is opt-in).

If `DIDIO_SKIP_TEA=1` is set, skip with a visible yellow warning. Re-run later
with `/check-tests <FXX>` to regenerate.

## Step 2 — Run each Wave in order

Parse the Wave manifest from the feature README. For each Wave N (starting
from 0), run:

```bash
didio run-wave <FXX> <N> developer
```

Wait for each Wave to exit before starting the next. If any Wave fails,
STOP the pipeline and report the failure to the user.

## Step 3 — Tech Lead

```bash
didio spawn-agent techlead <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

If the verdict is `REJECTED`, STOP and report.

## Step 4 — QA

```bash
didio spawn-agent qa <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

## Step 5 — Final report

Summarize to the user:
- Number of Waves executed
- Number of tasks completed
- Tech Lead verdict
- QA verdict
- Paths to review/qa reports
- Link: `didio dashboard` for visual audit

## Rules

- NEVER run Developer/TechLead/QA through the `Agent` tool — always use
  `didio spawn-agent` so they run in clean bash with persistent logs.
- NEVER skip a Wave. NEVER run Waves out of order.
- NEVER advance past a failing Wave.
- NEVER skip the readiness gate (Step 1.5) silently. The only valid bypass
  is `DIDIO_SKIP_READINESS=1` set explicitly by the user, with a visible
  yellow warning printed.
