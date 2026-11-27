# Feature F45 — Black Hawk Autonomous Card Advancement

**Status:** planned
**Owner:** @operator
**Priority:** MAX

## Goal

Black Hawk Alpha operates autonomously in a loop: triages incoming cards,
auto-promotes clear recommendations, starts pipelines for promoted cards,
and surfaces impediments/ambiguous decisions to the operator via the HTML
Command Center. The operator approves, rejects, or modifies from the board.

## Architecture

```
┌─ Autonomous Loop (didio blackhawk auto) ─────────────────────┐
│                                                                │
│  1. Scan incoming cards                                        │
│  2. For each: run triage (Alpha assessment)                    │
│  3. If recommendation = promote AND confidence >= threshold:   │
│     → auto-promote + start pipeline                            │
│  4. If recommendation = defer AND confidence >= threshold:     │
│     → auto-defer                                               │
│  5. If confidence < threshold OR needs_input:                  │
│     → create alert in Command Center (operator decides)        │
│  6. Monitor running pipelines for failures                     │
│     → surface failures as impediments                          │
│  7. Sleep interval, repeat                                     │
│                                                                │
│  Operator actions (via HTML board):                            │
│  - Approve suggested action → executes immediately             │
│  - Reject → card stays, Alpha re-evaluates next cycle          │
│  - Override → operator sets manual status                      │
│  - Send command → queued for Alpha to execute                  │
└────────────────────────────────────────────────────────────────┘
```

## Confidence Threshold

- `blackhawk.auto_confidence_threshold`: 0.8 (default)
- Alpha assessment includes `confidence: 0.0-1.0` field
- Above threshold: auto-execute recommendation
- Below threshold: surface to operator as alert
- `blackhawk.auto_advance`: true/false (kill switch)

## Command Center Protocol

```json
// Alert format (served via /api/alerts)
{
  "alert_id": "ALT-YYYYMMDD-NNN",
  "type": "needs_approval|failed_pipeline|low_confidence|escalation",
  "card_id": "WR-...",
  "title": "...",
  "description": "...",
  "suggestion": "didio blackhawk promote WR-...",
  "confidence": 0.65,
  "created_at": "ISO",
  "status": "pending|approved|rejected|expired"
}
```

Operator actions via POST:
- `POST /api/alerts/approve` → execute suggestion
- `POST /api/alerts/reject` → dismiss, Alpha re-evaluates
- `POST /api/alerts/override` → set manual status on card

## Waves

- **Wave 0**: F45-T01, F45-T02 (config + alert schema + server endpoints)
- **Wave 1**: F45-T03, F45-T04, F45-T05 (autonomous loop, alert engine, board UI)
- **Wave 2**: F45-T06, F45-T07 (E2E tests + docs)

## Dependency Graph

```
F45-T01 (config + schema)──→ F45-T03 (autonomous loop script)
F45-T02 (server endpoints) ─→ F45-T04 (alert engine)
                             └→ F45-T05 (board Command Center upgrade)
                                F45-T06 (E2E tests)
                                F45-T07 (CLI + docs + diagrams)
```

## Tasks

### Wave 0 — Foundation

**F45-T01: Config, Schema & Alert Store**
- Add to `didio.config.json`:
  - `blackhawk.auto_advance: true`
  - `blackhawk.auto_confidence_threshold: 0.8`
  - `blackhawk.auto_interval_minutes: 5`
  - `blackhawk.auto_max_promotions_per_cycle: 3`
- Create `schemas/alert.schema.json`
- Create `logs/warroom/alerts/` directory for alert JSON files
- Alert lifecycle: pending → approved/rejected/expired

**F45-T02: Server Alert Endpoints**
- `GET /api/alerts` — list pending alerts
- `POST /api/alerts/approve` — execute suggestion, mark approved
- `POST /api/alerts/reject` — mark rejected
- `POST /api/alerts/override` — set manual card status
- Alerts auto-expire after 24h if not acted on

### Wave 1 — Core (3 parallel tracks)

**F45-T03: Autonomous Loop Script (`bin/didio-blackhawk-auto.sh`)**
- Main loop: scan → triage → decide → execute/alert → sleep
- Uses existing `didio blackhawk triage` for assessment
- Reads confidence from assessment JSON
- Auto-promotes if confidence >= threshold
- Creates alert if confidence < threshold
- Monitors pipelines for failures between cycles
- Signal-based control: `logs/agents/signals/blackhawk.pause/resume/stop`
- Logs to `logs/agents/blackhawk-auto.log`

**F45-T04: Alert Engine (`lib/alert-engine.sh`)**
- `create_alert(type, card_id, title, description, suggestion, confidence)`
- `list_pending_alerts()` — returns JSON array
- `approve_alert(alert_id)` — executes suggestion command
- `reject_alert(alert_id)` — marks rejected
- `expire_stale_alerts(max_age_hours)` — cleanup
- Each alert is a JSON file in `logs/warroom/alerts/`

**F45-T05: Board Command Center Upgrade**
- Fetch from `/api/alerts` instead of deriving from data
- Show confidence score on each alert
- Color-code by confidence: red (<0.5), yellow (0.5-0.8), green (>0.8)
- Approve/Reject buttons POST to server
- Toast notification on action result
- Pending alert count badge in header

### Wave 2 — Validation

**F45-T06: E2E Tests**
- Test autonomous loop with mock triage responses
- Test alert creation and approval flow
- Test confidence threshold gating
- Test signal-based pause/resume
- Test alert expiration

**F45-T07: CLI, Docs & Diagrams**
- Wire `didio blackhawk auto` command
- Create F45-architecture.mmd and F45-journey.mmd
- Update README and orchestrator.md

## Global Acceptance Criteria

- [ ] `didio blackhawk auto` starts autonomous loop
- [ ] High-confidence cards auto-promoted without operator input
- [ ] Low-confidence cards surface as alerts in Command Center
- [ ] Operator can approve/reject alerts from HTML board
- [ ] Failed pipelines surface as alerts automatically
- [ ] Autonomous loop respects pause/resume signals
- [ ] Kill switch `blackhawk.auto_advance: false` stops all auto-actions
- [ ] E2E tests pass with mock triage data
- [ ] Alert expiration cleans up stale alerts
