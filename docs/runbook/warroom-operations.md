# War Room Operations Runbook

**Last updated:** 2026-11-26
**Applies to:** claude-didio-config framework

---

## 1. Quick Start

Five commands to get started with the War Room:

```bash
# 1. Create a card
didio warroom add "Refactor auth module" --body "Session handling needs rework" --priority high --tags "auth,refactor"

# 2. List incoming cards
didio warroom list --status incoming

# 3. Triage all incoming cards (dry-run first)
didio blackhawk triage --dry-run

# 4. Promote a triaged card to a feature
didio blackhawk promote WR-20261126-001

# 5. Check board status
didio warroom list
```

---

## 2. Card Lifecycle

A War Room card moves through the following statuses:

```
                     +---> promoted ---> (feature pipeline)
                     |
incoming ---> triaging ---> deferred ---> archived
                     |
                     +---> archived
                     |
                     +---> triaging (needs_input -- stays for manual review)
```

### Status Definitions

| Status | Meaning |
|--------|---------|
| `incoming` | New card, waiting for triage |
| `triaging` | Black Hawk Alpha is assessing the card |
| `promoted` | Card accepted and converted to a feature in `tasks/features/` |
| `deferred` | Card postponed (auto-archived after `defer_auto_archive_days`) |
| `archived` | Card closed -- no longer active |

### Assessment Recommendations

When Black Hawk Alpha triages a card, it produces one of these recommendations:

| Recommendation | Action |
|---------------|--------|
| `promote` | Create feature directory, update card to `promoted` |
| `defer` | Move card to `deferred`, record rationale |
| `archive` | Move card to `archived` |
| `needs_input` | Card stays in `triaging`, questions recorded in assessment |

---

## 3. CLI Reference

### `didio warroom` -- Card Management

#### `didio warroom add`

Create a new War Room card. Card ID is auto-generated as `WR-YYYYMMDD-NNN`.

```bash
didio warroom add "title" [OPTIONS]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--body "text"` | Full description (markdown allowed) | empty |
| `--tags "a,b,c"` | Comma-separated tags | none |
| `--priority low\|medium\|high\|max` | Priority suggestion | null |
| `--source operator\|agent\|external` | Card origin | `operator` |

**Examples:**

```bash
# Minimal card
didio warroom add "Fix dashboard crash on empty state"

# Full card with all options
didio warroom add "MCP Connector: Jira integration" \
  --body "Build a Jira MCP connector for syncing issues" \
  --tags "mcp,jira,corporate,integration" \
  --priority medium \
  --source operator
```

#### `didio warroom list`

List War Room cards. By default hides archived cards.

```bash
didio warroom list [OPTIONS]
```

| Option | Description | Default |
|--------|-------------|---------|
| `--status <status>` | Filter by status | all non-archived |
| `--all` | Include archived cards | false |
| `--format table\|json` | Output format | `table` |

**Examples:**

```bash
# Default table view (non-archived)
didio warroom list

# Filter by status
didio warroom list --status incoming
didio warroom list --status promoted
didio warroom list --status deferred

# JSON output for scripting
didio warroom list --format json

# Include archived
didio warroom list --all
```

#### `didio warroom show`

Display full details of a card, including Black Hawk Alpha assessment.

```bash
didio warroom show <card-id>
```

**Example:**

```bash
didio warroom show WR-20261126-001
# Output:
# Card ID:    WR-20261126-001
# Title:      Black Hawk Bravo -- Intelligence Agent
# Status:     promoted
# Source:     operator
# Priority:   high
# Tags:       squad-expansion, agents, bravo
# Created:    2026-11-26T...
#
# Body:
# ...
#
# Black Hawk Alpha Assessment:
#   Recommendation: promote
#   Priority:       high
#   Rationale:      Squad expansion, CI/CD intelligence multiplier
#   Promoted as:    F36 -- Black Hawk Bravo -- Intelligence Agent
```

#### `didio warroom move`

Manually move a card to a new status.

```bash
didio warroom move <card-id> <status>
```

Valid statuses: `incoming`, `triaging`, `promoted`, `deferred`, `archived`.

**Examples:**

```bash
# Reset a card back to incoming (e.g., after a dry-run left it in triaging)
didio warroom move WR-20261126-001 incoming

# Manually archive a card
didio warroom move WR-20261126-003 archived
```

---

### `didio blackhawk` -- Black Hawk Alpha Operations

#### `didio blackhawk triage`

Run Black Hawk Alpha triage on War Room cards.

```bash
didio blackhawk triage [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--card <id>` | Triage a single card by ID |
| `--auto` | Continuous loop (runs every `triage_interval_minutes`) |
| `--dry-run` | Preview without spawning agents or creating features |
| (no flags) | Batch triage all `incoming` cards |

**Exit codes:** 0 = success, 1 = runtime error, 2 = config/preflight issue.

**Examples:**

```bash
# Triage a single card
didio blackhawk triage --card WR-20261126-001

# Batch triage all incoming cards
didio blackhawk triage

# Dry-run to preview (does NOT spawn agents)
didio blackhawk triage --dry-run

# Continuous auto-triage (runs every N minutes from config)
didio blackhawk triage --auto
```

**Batch triage output:**

```
[blackhawk-triage] Batch triage: max_promotions=2 current=0 remaining=2
[blackhawk-triage] Processing WR-20261126-001...
[blackhawk-triage] Processing WR-20261126-002...
...
Triage complete: 6 cards processed (promote=3 defer=3 archive=0 needs_input=0)
[blackhawk-triage] Summary: logs/warroom/triage-20261126-001.json
```

#### `didio blackhawk promote`

Promote a triaged card to a Standard Board feature.

```bash
didio blackhawk promote <card-id>
```

**Requirements:**
- Card must exist in `logs/warroom/cards/`
- Card must have `overlord_assessment.recommendation = "promote"`

**Actions performed:**
1. Scans `tasks/features/` for the next available feature ID
2. Creates `tasks/features/<FXX>-<slug>/` directory
3. Creates `tasks/features/<FXX>-<slug>/<FXX>-README.md`
4. Updates card JSON: `status=promoted`, `promoted_to=<FXX>`

**Example:**

```bash
didio blackhawk promote WR-20261126-001
# Output:
# Promoted WR-20261126-001 -> F36: Black Hawk Bravo -- Intelligence Agent
#   Directory: tasks/features/F36-black-hawk-bravo-intelligence-agent/
#   README: tasks/features/F36-black-hawk-bravo-intelligence-agent/F36-README.md
```

#### `didio blackhawk defer`

Defer a War Room card.

```bash
didio blackhawk defer <card-id>
```

**Actions performed:**
1. Updates card `status` to `deferred`
2. Records rationale from `overlord_assessment` (or "Deferred by operator" if no assessment)
3. Updates `updated_at` timestamp

**Example:**

```bash
didio blackhawk defer WR-20261126-002
# Output:
# Deferred WR-20261126-002: DOB Benchmark real-world validation
#   Rationale: Needs stable corporate baselines first
```

#### `didio blackhawk monitor`

Governance pattern detection. Scans decision/review logs and raises strategic
War Room cards when patterns are detected.

```bash
didio blackhawk monitor [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--since YYYY-MM-DD` | Only analyze after this date |
| `--dry-run` | Detect patterns without creating cards |
| `--continuous` | Loop every N minutes |
| `--interval MINUTES` | Override loop interval (default: from config or 30) |

**Pattern detectors:**

| # | Pattern | Trigger |
|---|---------|---------|
| 1 | Repeated challenges | 3+ GateKeeper challenges in 7 days |
| 2 | Blocked pipelines | 2+ decisions blocked with similar reason |
| 3 | Low confidence | Average confidence < 0.6 in last 5 reviews |
| 4 | Escalation frequency | 2+ escalations in last 10 decisions |
| 5 | Persistent blocked flags | Any flag unresolved for >24h |
| 6 | Token budget pressure | `token-schedule-suggestion.json` status=critical |

**Example:**

```bash
didio blackhawk monitor --dry-run
didio blackhawk monitor --since 2026-11-25
didio blackhawk monitor --continuous --interval 15
```

---

## 4. Configuration

All War Room and Black Hawk Alpha settings live in the `blackhawk` section
of `didio.config.json` (project root).

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `blackhawk.enabled` | boolean | `true` | Enable/disable Black Hawk Alpha |
| `blackhawk.auto_triage` | boolean | `true` | Allow auto-triage mode (`--auto`) |
| `blackhawk.triage_interval_minutes` | integer | `30` | Minutes between auto-triage cycles |
| `blackhawk.knowledge_sources` | string[] | `["adr","learnings","retrospectives"]` | Context sources for triage assessment |
| `blackhawk.max_concurrent_promotions` | integer | `2` | Max cards that can be in `promoted` status simultaneously |
| `blackhawk.promotion_requires_confirmation` | boolean | `false` | If true, promotions stay in `triaging` until operator confirms |
| `blackhawk.defer_auto_archive_days` | integer | `30` | Days before deferred cards auto-archive |
| `blackhawk.auto_launch` | boolean | `true` | Auto-start Black Hawk Alpha at machine boot |
| `blackhawk.silent_mode` | boolean | `false` | Suppress notifications |
| `blackhawk.avatar_path` | string | `""` | Custom avatar image path |
| `blackhawk.notification_sound` | boolean | `true` | Play sound on notifications |
| `blackhawk.chat_history_days` | integer | `30` | Days of chat history to retain |
| `blackhawk.desktop_app.width` | integer | `400` | Desktop window width |
| `blackhawk.desktop_app.height` | integer | `600` | Desktop window height |
| `blackhawk.desktop_app.position` | string | `"bottom-right"` | Desktop window position |

**Example configuration (current):**

```json
{
  "blackhawk": {
    "enabled": true,
    "auto_triage": true,
    "triage_interval_minutes": 30,
    "knowledge_sources": ["adr", "learnings", "retrospectives"],
    "max_concurrent_promotions": 2,
    "promotion_requires_confirmation": false,
    "defer_auto_archive_days": 30
  }
}
```

---

## 5. Dashboard Integration

The Black Hawk Desktop app (Tauri + React) provides a visual War Room board.

### Hooks

| Hook | File | Purpose |
|------|------|---------|
| `useWarroomState` | `dashboard/src/hooks/useWarroomState.ts` | Fetches card data, builds board columns, auto-refreshes every 3s |
| `useWarroomActions` | `dashboard/src/hooks/useWarroomActions.ts` | Provides mutations: `useCreateCard`, `useUpdateCard`, `useTriageCard` |

### Board Columns

The dashboard organizes cards into Kanban columns matching the card statuses:
`incoming`, `triaging`, `promoted`, `deferred`, `archived`.

### Real-time Updates

- Cards auto-refresh every 3 seconds (`refetchInterval: 3000`)
- Stale time is 1.5 seconds (`staleTime: 1500`)
- Background refetch is enabled -- board updates even when tab is not focused

### Dashboard Actions

From the dashboard UI, operators can:

- **Create a card** via form (calls `useCreateCard`)
- **Update card fields** inline (calls `useUpdateCard`)
- **Request triage** for a card (calls `useTriageCard`, sets status to `triaging`)

CLI triage results appear in the dashboard automatically through the shared
card JSON files in `logs/warroom/cards/`.

---

## 6. Troubleshooting

### Agent spawn fails (exit code 126)

**Symptom:** `didio blackhawk triage --card <id>` outputs "WARN: Black Hawk Alpha
agent exited with code 126" and the card stays in `triaging` with no assessment.

**Cause:** The triage spawns a Claude Code agent via `didio-spawn-agent.sh`. This
fails when running from within a nested Claude Code session (the `claude` CLI binary
is unavailable or blocked).

**Fix:**
1. Run triage from a standalone terminal (not inside Claude Code)
2. Or manually inject an assessment into the card JSON and then run promote:
   ```bash
   # Edit the card JSON to add overlord_assessment, then:
   didio blackhawk promote WR-20261126-001
   ```

### Rate limit / token budget

**Symptom:** Triage or agent spawn fails with rate-limit or budget errors.

**Cause:** The LLM API rate limit or session token budget is exhausted.

**Fix:**
1. Check token budget: `cat logs/agents/token-schedule-suggestion.json`
2. If `status=critical`, pause pipelines and wait for budget to replenish
3. Use `didio blackhawk triage --dry-run` to validate the pipeline without
   consuming tokens
4. The `blackhawk monitor` will raise a strategic card automatically when
   token budget is critical

### Stuck card in "triaging" status

**Symptom:** A card is stuck in `triaging` after a failed triage run or dry-run.

**Cause:** The `--dry-run` flag transitions cards to `triaging` but does not
revert them. Also happens if the agent spawn fails mid-triage.

**Fix:**

```bash
# Reset the card back to incoming
didio warroom move WR-20261126-001 incoming

# Then re-triage
didio blackhawk triage --card WR-20261126-001
```

### Missing assessment (card triaged but no overlord_assessment)

**Symptom:** `didio warroom show <id>` shows "not yet triaged" even though
the card status is `triaging` or `promoted`.

**Cause:** The Black Hawk Alpha agent output could not be parsed (no valid
JSON assessment block in the agent response).

**Fix:**
1. Check the agent output log: `logs/warroom/.triage-output-<card-id>.txt`
   (if it still exists -- cleaned up after successful parse)
2. The card will have a fallback assessment with `recommendation: needs_input`
   and `questions: ["Agent output could not be parsed. Please review manually."]`
3. Manually inject the assessment:
   ```bash
   # Edit logs/warroom/cards/<card-id>.json
   # Set overlord_assessment with the correct recommendation, priority, rationale
   # Then promote or defer as needed
   didio blackhawk promote <card-id>
   ```

### Card not found

**Symptom:** `Error: card 'WR-...' not found`

**Cause:** Card JSON file does not exist in `logs/warroom/cards/`.

**Fix:**
1. Verify the card ID format: must be `WR-YYYYMMDD-NNN`
2. Check the cards directory: `ls logs/warroom/cards/`
3. Ensure `DIDIO_PROJECT_ROOT` is set correctly if running from outside the
   project directory

### Promotion creates wrong feature ID

**Symptom:** Feature ID collides with an existing feature or skips numbers.

**Cause:** `_next_feature_id()` scans `tasks/features/` directories. If
directories were manually created or deleted, the sequence may be unexpected.

**Fix:** The promote script has a race-condition guard that increments
the feature ID if the directory already exists. If the sequence is wrong,
manually rename the feature directory and update the card's `promoted_to` field.

### Preflight check fails (exit code 2)

**Symptom:** Triage exits with code 2 and a preflight error message.

**Cause:** One of these preconditions failed:
- `didio.config.json` not found
- `blackhawk.enabled` is `false`
- `python3` not in PATH
- `didio-spawn-agent.sh` not found
- Cards directory cannot be created

**Fix:** Address the specific error message. Most commonly:
```bash
# Ensure config exists
ls didio.config.json

# Check blackhawk is enabled
python3 -c "import json; d=json.load(open('didio.config.json')); print(d['blackhawk']['enabled'])"

# Verify python3
python3 --version
```

---

## 7. Architecture Notes

### File Paths

| Path | Purpose |
|------|---------|
| `logs/warroom/cards/` | Card JSON files (`WR-YYYYMMDD-NNN.json`) |
| `logs/warroom/triage-*.json` | Triage batch summaries |
| `logs/warroom/.triage-context.md` | Auto-generated knowledge context for triage |
| `logs/warroom/.triage-task-*.md` | Temporary task payload for agent spawn |
| `logs/warroom/.triage-output-*.txt` | Temporary agent output (deleted after parse) |
| `schemas/warroom-card.schema.json` | Card JSON schema (source of truth for valid fields) |
| `didio.config.json` | Framework config (contains `blackhawk` section) |
| `bin/didio-warroom.sh` | Card management CLI |
| `bin/didio-blackhawk.sh` | Black Hawk Alpha sub-routing dispatcher |
| `bin/didio-blackhawk-triage.sh` | Triage CLI (single, batch, auto modes) |
| `bin/didio-blackhawk-promote.sh` | Promotion script (card to feature) |
| `bin/didio-blackhawk-defer.sh` | Deferral script |
| `bin/didio-blackhawk-monitor.sh` | Governance pattern detection |
| `lib/blackhawk-triage.sh` | Core triage functions (assess, promote, batch) |
| `lib/blackhawk-governance.sh` | Governance pattern detection library |
| `dashboard/src/hooks/useWarroomState.ts` | React hook: board state polling |
| `dashboard/src/hooks/useWarroomActions.ts` | React hook: card mutations |
| `tasks/features/<FXX>-<slug>/` | Feature directories created by promotion |

### Data Flow

```
Operator / Agent / External
        |
        v
  didio warroom add  --->  logs/warroom/cards/WR-*.json  (status: incoming)
        |
        v
  didio blackhawk triage
        |
        +--- gather_knowledge() ---> reads ADRs, learnings, features, decisions
        |                            writes logs/warroom/.triage-context.md
        |
        +--- assess_card() ---------> spawns Black Hawk Alpha agent
        |                             parses JSON assessment from output
        |                             writes overlord_assessment to card
        |                             sets status to promoted/deferred/archived/triaging
        |
        +--- if promote:
        |      promote_card() -------> calls didio-blackhawk-promote.sh
        |                              allocates next feature ID
        |                              creates tasks/features/<FXX>-<slug>/
        |                              creates <FXX>-README.md
        |                              updates card: promoted_to, status=promoted
        |
        +--- writes triage summary --> logs/warroom/triage-*.json
        |
        v
  Dashboard (auto-refresh every 3s) reads logs/warroom/cards/*.json
```

### Card JSON Schema

Cards conform to `schemas/warroom-card.schema.json`. Key fields:

| Field | Type | Description |
|-------|------|-------------|
| `card_id` | string | Format: `WR-YYYYMMDD-NNN` |
| `title` | string | Card title (1-200 chars) |
| `body` | string | Full description (markdown) |
| `source` | enum | `operator`, `agent`, `external` |
| `status` | enum | `incoming`, `triaging`, `promoted`, `deferred`, `archived` |
| `priority_suggestion` | enum/null | `low`, `medium`, `high`, `max` |
| `overlord_assessment` | object/null | Black Hawk Alpha's assessment (see below) |
| `promoted_to` | string/null | Feature ID if promoted (e.g. `F36`) |
| `tags` | string[] | Arbitrary tags |
| `source_agent` | string/null | Agent name if source is `agent` |
| `source_feature` | string/null | Feature ID that triggered the card |

### Assessment Object

When present, `overlord_assessment` contains:

| Field | Type | Description |
|-------|------|-------------|
| `assessed_at` | ISO datetime | When the assessment was made |
| `recommendation` | enum | `promote`, `defer`, `archive`, `needs_input` |
| `priority` | enum | `low`, `medium`, `high`, `max` |
| `rationale` | string | 2-3 sentence justification |
| `promoted_as` | string/null | Feature label if promoted (e.g. `F36 -- Auth refactor`) |
