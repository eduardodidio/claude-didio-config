---
name: create-feature
description: Run the full Architect -> Waves -> TechLead -> QA pipeline for a new feature
kind: command
targets: [claude, codex]
argument-hint: <FXX> <feature description>
---

You are dispatching a feature pipeline for project **{{PROJECT_NAME}}**.

The user asked for feature: **$ARGUMENTS**

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

### Step 3 — Launch the pipeline in background

```bash
didio run-pipeline <FXX> "tasks/features/<FXX>-_tmp-brief.md" &
PIPELINE_PID=$!
echo "PIPELINE_PID=$PIPELINE_PID"
```

Print to the user:

> Launching pipeline in background (PID: $PIPELINE_PID). Monitoring progress...
> State file: `logs/agents/pipeline-<FXX>.state.json`
> Signal dir: `logs/agents/signals/` (create `<FXX>.pause` or `<FXX>.cancel` to control)

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
  > [pipeline] Stage transition: architect -> readiness (running)
- If `stage_detail` changed (e.g. wave progress), report it:
  > [pipeline] Progress: wave 2 of 4
- If `status` changed to `completed`:
  > Pipeline complete for <FXX>.
  > Run `didio pipeline-status <FXX>` for details.
  Break from the monitor loop and proceed to Step 5.
- If `status` changed to `failed`:
  > Pipeline FAILED at stage: <stage>
  > Error: <error from state file>
  > Run `didio pipeline-status <FXX>` for details.
  Break from the monitor loop.
- If `status` changed to `escalated`:
  > Pipeline ESCALATED at stage: <stage>
  > Error: <error from state file>
  > Human review required. See `didio pipeline-status <FXX>`.
  Break from the monitor loop.
- If `status` changed to `paused`:
  > Pipeline PAUSED: <error from state file>
  > Resume with: `touch logs/agents/signals/<FXX>.resume`
  Break from the monitor loop.

**If the operator types during monitoring:** pause the monitor polling,
respond to the operator's message, then resume polling. The pipeline
CONTINUES running in background regardless of monitor state.

### Step 5 — Final summary (dispatch mode)

When the pipeline completes (status=`completed`), read the final state and
summarize:

- Feature: `<FXX>`
- Stages completed: (list from `stages_completed`)
- Duration: (from `started_at` to `updated_at`)
- State file: `logs/agents/pipeline-<FXX>.state.json`
- Dashboard: `didio dashboard`

> Pipeline complete. Run `didio pipeline-status <FXX>` for details.

---

## Legacy Inline Mode (pipeline.autonomous = false or absent)

### Step 10 — Run full inline pipeline

When `pipeline.autonomous` is `false` or absent, execute the full inline
pipeline directly. This is the original behavior preserved for backward
compatibility.

Follow the complete inline pipeline documented in
`skills/create-feature-legacy.md`:

**Step 10.0 — Handler Strategic Gate (conditional)**

Before any agent runs, check if the Handler strategic orchestrator is enabled:

```bash
HANDLER_ENABLED=$(python3 -c "import json; c=json.load(open('didio.config.json')); print(c.get('meta_agents',{}).get('handler',{}).get('enabled', False))" 2>/dev/null || echo "False")
```

If `HANDLER_ENABLED` is `False` (default): **skip this step silently** and proceed to Step 10.1.

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
   didio handler <FXX> logs/decisions/_requests/<FXX>-<timestamp>.md
   ```

3. Find the latest decision record in `logs/decisions/D-*.json`.

4. Read its `status` field:
   - If `escalated`: **STOP the pipeline.** Print:
     > Handler/GateKeeper escalated this decision. Human review required.
     > Decision: logs/decisions/<id>.json
     > Governance: logs/governance/G-<id>.json
   - If `executed` or `reviewed` with governance verdict `agree`: **proceed** to Step 10.1.
   - If governance verdict `challenge` was resolved: **proceed** to Step 10.1.

5. Read the `actions` array. If the Handler recommends a different action
   than `create-feature` (e.g. `plan-feature`, `skip`, `research`),
   **STOP** and inform the user:
   > Handler recommends: <action> instead of create-feature.
   > Rationale: <rationale from decision record>
   > Run the recommended command or override with DIDIO_SKIP_HANDLER=1.

**Bypass:** if `DIDIO_SKIP_HANDLER=1` is set, skip with a visible yellow warning:
> Warning: Handler gate bypassed via DIDIO_SKIP_HANDLER=1

**Step 10.1 — Architect**

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

**Step 10.1.5 — Readiness gate (pre-Wave audit)**

Before firing Wave 0, run the readiness audit:

```bash
/check-readiness <FXX>
```

If the verdict is `BLOCKED`: STOP the pipeline, print the path of
`readiness-report.md`, tell the user to fix the plan.

If `DIDIO_SKIP_READINESS=1` is set, skip with a yellow warning.

**Step 10.1.7 — TEA gate (test architect, opt-in)**

If `didio.config.json:tea.enabled` is `true` AND `DIDIO_SKIP_TEA` is not set:

```bash
didio spawn-agent tea <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

If `tea.enabled` is `false`, skip silently. If `DIDIO_SKIP_TEA=1`, skip with warning.

**Step 10.2 — Run each Wave in order**

```bash
didio run-wave <FXX> <N> developer
```

Wait for each Wave before starting the next. If any Wave fails, STOP.

**Step 10.3 — Tech Lead**

```bash
didio spawn-agent techlead <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

If verdict is `REJECTED`, STOP and report.

**Step 10.4 — QA**

```bash
didio spawn-agent qa <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

**Step 10.5 — Final report**

Summarize to the user:
- Number of Waves executed
- Number of tasks completed
- Tech Lead verdict
- QA verdict
- Paths to review/qa reports
- Link: `didio dashboard` for visual audit

---

## Rules

- NEVER run Developer/TechLead/QA through the `Agent` tool — always use
  `didio spawn-agent` so they run in clean bash with persistent logs.
- NEVER skip a Wave. NEVER run Waves out of order.
- NEVER advance past a failing Wave.
- NEVER skip the readiness gate silently. The only valid bypass
  is `DIDIO_SKIP_READINESS=1` set explicitly by the user, with a visible
  yellow warning printed.
- NEVER skip the Handler gate silently when enabled. The only valid bypass
  is `DIDIO_SKIP_HANDLER=1` set explicitly by the user, with a visible warning.
- In dispatch mode, the pipeline CONTINUES in background regardless of
  whether the monitor is active. Pausing the monitor does NOT pause the
  pipeline. Use signal files (`<FXX>.pause`, `<FXX>.cancel`) to control
  the pipeline itself.
