---
name: plan-feature
description: Plan a new feature (Architect only) — produces tasks with Status=planned, no Waves executed
kind: command
targets: [claude, codex]
argument-hint: <FXX> <feature description>
---

You are dispatching a **planning-only** pipeline for project **{{PROJECT_NAME}}**.

The user asked to plan feature: **$ARGUMENTS**

## Step 0 — Determine execution mode

Check whether autonomous pipeline mode is enabled:

```bash
AUTONOMOUS=$(python3 -c "
import json, os
try:
    c = json.load(open('didio.config.json'))
    print(str(c.get('pipeline', {}).get('autonomous', False)).lower())
except Exception:
    print('false')
" 2>/dev/null || echo "false")
echo "pipeline.autonomous=$AUTONOMOUS"
```

- If `AUTONOMOUS` is `true`: proceed to **Dispatch Mode** (Step 1).
- If `AUTONOMOUS` is `false` (default, or config absent): proceed to
  **Legacy Inline Mode** (Step 10).

---

## Dispatch Mode (pipeline.autonomous = true)

### Step 1 — Extract feature ID and brief

Extract the feature ID (e.g. `F07`) and description from `$ARGUMENTS`.
If the user did not supply an ID, pick the next free `F<NN>` by looking at
`tasks/features/`.

### Step 2 — Write the brief file

```bash
mkdir -p tasks/features
cat > "tasks/features/<FXX>-_tmp-brief.md" <<'BRIEF'
<feature description from $ARGUMENTS>
BRIEF
```

### Step 3 — Launch the pipeline in background (plan-only)

For plan-only, we still use `didio run-pipeline` but the pipeline will only
execute the Handler gate + Architect stages. We pass `--skip-readiness
--skip-tea` and set `DIDIO_PLAN_ONLY=true`:

```bash
DIDIO_PLAN_ONLY=true didio run-pipeline <FXX> "tasks/features/<FXX>-_tmp-brief.md" --skip-readiness --skip-tea &
PIPELINE_PID=$!
echo "PIPELINE_PID=$PIPELINE_PID"
```

Print to the user:

> Launching plan-only pipeline in background (PID: $PIPELINE_PID). Monitoring progress...
> State file: `logs/agents/pipeline-<FXX>.state.json`

### Step 4 — Monitor mode

Read `pipeline.monitor_poll_interval_secs` from `didio.config.json` (default: 15).

Enter a polling loop:

```bash
POLL_INTERVAL=$(python3 -c "
import json
try:
    c = json.load(open('didio.config.json'))
    print(c.get('pipeline', {}).get('monitor_poll_interval_secs', 15))
except Exception:
    print(15)
" 2>/dev/null || echo "15")
```

Repeatedly poll the state file every `$POLL_INTERVAL` seconds:

```bash
cat logs/agents/pipeline-<FXX>.state.json
```

**On each poll:**
- Compare `stage` and `status` with the previous poll.
- If a **stage transition** occurred, report it:
  > [pipeline] Stage transition: handler_gate -> architect (running)
- If `status` changed to `completed`:
  > Plan-only pipeline complete for <FXX>.
  > Run `didio pipeline-status <FXX>` for details.
  Break from the monitor loop and proceed to Step 5.
- If `status` changed to `failed`:
  > Pipeline FAILED at stage: <stage>
  > Error: <error from state file>
  Break from the monitor loop.
- If `status` changed to `escalated`:
  > Pipeline ESCALATED at stage: <stage>
  > Human review required. See `didio pipeline-status <FXX>`.
  Break from the monitor loop.

**If the operator types during monitoring:** pause the monitor polling,
respond to the operator's message, then resume polling. The pipeline
CONTINUES running in background regardless of monitor state.

### Step 5 — Final summary (dispatch mode)

When the pipeline completes (status=`completed`), read the final state and
the feature README, then summarize:

- Feature ID + slug
- Number of tasks planned + number of waves
- Path: `tasks/features/<FXX>-<slug>/`
- Next step: run `/create-feature <FXX>` to execute the plan
- Dashboard: `didio dashboard`

> Pipeline complete. Run `didio pipeline-status <FXX>` for details.

---

## Legacy Inline Mode (pipeline.autonomous = false or absent)

### Step 10 — Run inline planning pipeline

When `pipeline.autonomous` is `false` or absent, execute the planning
pipeline directly. This is the original behavior preserved for backward
compatibility.

Follow the complete inline pipeline documented in
`skills/plan-feature-legacy.md`:

**Step 10.0 — Handler Strategic Gate (conditional)**

```bash
HANDLER_ENABLED=$(python3 -c "import json; c=json.load(open('didio.config.json')); print(c.get('meta_agents',{}).get('handler',{}).get('enabled', False))" 2>/dev/null || echo "False")
```

If `HANDLER_ENABLED` is `False` (default): skip silently, proceed to Step 10.1.

If `True`:
1. Write a decision request to `logs/decisions/_requests/<FXX>-<timestamp>.md`
2. Run `didio handler <FXX> <request-file>`
3. Check decision status -- escalated stops, executed/reviewed proceeds
4. Check actions -- if Handler recommends something other than plan/create, stop

**Bypass:** if `DIDIO_SKIP_HANDLER=1` is set, skip with a visible yellow warning.

**Step 10.1 — Architect (PLAN_ONLY)**

Extract the feature ID and description from `$ARGUMENTS`. If no ID supplied,
pick the next free `F<NN>`.

Write brief to `tasks/features/<FXX>-_tmp-brief.md`, then run:

```bash
DIDIO_PLAN_ONLY=true didio spawn-agent architect <FXX> tasks/features/<FXX>-_tmp-brief.md
```

Wait for it to finish. Verify:
- `tasks/features/<FXX>-*/<FXX>-README.md` exists with `**Status:** planned`
- Each `<FXX>-TYY.md` has User Story, Dev Notes, Testing sections

Delete the `_tmp-brief.md`.

**Step 10.2 — Final report**

Summarize to the user:
- Feature ID + slug
- Number of tasks planned + number of waves
- Path: `tasks/features/<FXX>-<slug>/`
- Next step: run `/create-feature <FXX>` to execute the plan
- Link: `didio dashboard` for visual audit

---

## Rules

- NEVER run Developer/TechLead/QA in this flow (planning only).
- NEVER run `didio run-wave` in this flow.
- ALWAYS set `DIDIO_PLAN_ONLY=true` when spawning the Architect here.
- NEVER skip the Handler gate silently when enabled. The only valid bypass
  is `DIDIO_SKIP_HANDLER=1` set explicitly by the user, with a visible warning.
- In dispatch mode, the pipeline CONTINUES in background regardless of
  whether the monitor is active. Use signal files to control the pipeline.
