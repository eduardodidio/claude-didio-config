---
description: Run the full Narrative Designer? → Architect → Waves → TechLead → QA pipeline for a new feature
argument-hint: <FXX> <feature description>
---

You are orchestrating the claude-didio-config 5-agent Waves workflow for
project **{{PROJECT_NAME}}**.

The user asked for feature: **$ARGUMENTS**

## Your job (non-negotiable pipeline)

For each feature you execute EXACTLY this pipeline. Do not improvise.

1. **Narrative Designer** (conditional) runs BEFORE the Architect when the
   brief mentions narrative. See Step 0 for the heuristic.
2. **Architect** plans minimal tasks grouped in parallel Waves.
3. **Wave 0 includes ALL permissions, scaffolding, and dependencies** the
   later Waves need, so Waves 1..N run without interruption.
4. **Developer** implements each task.
5. **TechLead** reviews all tasks.
6. **QA** validates end-to-end and fills test gaps.

Constraints:
- Tasks must be **as small as possible** while still self-contained.
- Waves are **independent** — tasks in the same Wave must not touch each
  other's files.
- **Backend and frontend in the same Wave** whenever they don't share files.
- Every agent runs in a **clean bash context** via `didio spawn-agent` — you
  do NOT use the Agent tool for these; you shell out to `didio`.

## Step -1 — T-800 Strategic Gate (conditional)

Before any agent runs, check if the T-800 strategic orchestrator is enabled:

```bash
T800_ENABLED=$(python3 -c "import json; c=json.load(open('didio.config.json')); print(c.get('meta_agents',{}).get('t800',{}).get('enabled', False))" 2>/dev/null || echo "False")
```

If `T800_ENABLED` is `False` (default): **skip this step silently** and proceed to Step 0.

If `True`:
1. Write a decision request file to `logs/decisions/_requests/<FXX>-<timestamp>.md`:
   ```markdown
   # Decision Request: <FXX>
   **Type:** feature_start
   **Feature:** <description from $ARGUMENTS>
   **Requested at:** <ISO timestamp>
   **Pipeline:** create-feature (full: Architect -> Waves -> TechLead -> QA)
   ```

2. Run:
   ```bash
   didio t800 <FXX> logs/decisions/_requests/<FXX>-<timestamp>.md
   ```

3. Find the latest decision record in `logs/decisions/D-*.json`.

4. Read its `status` field:
   - If `escalated`: **STOP the pipeline.** Print:
     > T-800/T-1000 escalated this decision. Human review required.
     > Decision: logs/decisions/<id>.json
     > Governance: logs/governance/G-<id>.json
   - If `executed` or `reviewed` with governance verdict `agree`: **proceed** to Step 0.
   - If governance verdict `challenge` was resolved: **proceed** to Step 0.

5. Read the `actions` array. If the T-800 recommends a different action
   than `create-feature` (e.g. `plan-feature`, `skip`, `research`),
   **STOP** and inform the user:
   > T-800 recommends: <action> instead of create-feature.
   > Rationale: <rationale from decision record>
   > Run the recommended command or override with DIDIO_SKIP_T800=1.

**Bypass:** if `DIDIO_SKIP_T800=1` is set, skip with a visible yellow warning:
> Warning: T-800 gate bypassed via DIDIO_SKIP_T800=1

## Step 0 — Narrative Designer (conditional)

Before running the Architect, detect whether this feature touches
narrative.

**Heuristic:** if the text in `tasks/features/<FXX>-_tmp-brief.md`
(the brief file) matches the regex
`/dlg|dialogue|narrative|scene|chapter|cinematic|cutscene/i`, ask
the user literally:

> "essa feature toca narrativa? [s/N]"

If the answer starts with `s` (or is `sim`/`yes`/`y`), run:

```bash
didio spawn-agent narrative-designer <FXX> tasks/features/<FXX>-_tmp-brief.md
```

Wait for it to finish. Verify that at least one `.md` file was created
under `docs/game-design/narrative/`. If not, STOP and report — the
narrative output is a hard dependency of the Architect on narrative
features.

If the answer is empty, `n`, `não`, `no`, or the heuristic did not
match, SKIP this step silently and proceed to Step 1.

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

## Step 1.5 — TEA (Test Architect) — conditional

After the Architect completes and BEFORE Wave 0, check if TEA is enabled:

```bash
python3 -c "import json; c=json.load(open('didio.config.json')); print(c.get('tea',{}).get('enabled', False))"
```

If the output is `True`, ask the user:

> "rodar TEA (Test Architect) para gerar o test-plan? [s/N]"

If the answer starts with `s` (or is `sim`/`yes`/`y`), run:

```bash
didio spawn-agent tea <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

Wait for it to finish. Verify that `tasks/features/<FXX>-*/<FXX>-test-plan.md` was created.
If TEA fails or the file is missing, warn the user but continue — TEA is advisory, not blocking.

If `tea.enabled = false` OR the user answers `n`, skip silently.

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
- NEVER skip the narrative heuristic. If the brief contains any of
  `dlg/dialogue/narrative/scene/chapter/cinematic/cutscene` and you don't
  ask the user, that is a bug.
- NEVER skip the T-800 gate silently when enabled. The only valid bypass
  is `DIDIO_SKIP_T800=1` set explicitly by the user, with a visible warning.
