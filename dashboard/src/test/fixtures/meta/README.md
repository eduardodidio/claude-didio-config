# Meta-agent fixture corpus — answer key

Synthetic-but-schema-valid corpus for the F17 monitoring harness Vitests
(`metaMetrics.test.ts`, `metaSources.test.ts`). **Never** read the live
`logs/` artifacts from these tests — this directory is the only input.

All numbers below are exact and were chosen to be hand-assertable
(round averages). Recompute by hand if you change any fixture file.

## Corpus shape

- `decisions/D-20260101-00{1..4}.json` — 4 decisions, 4 distinct `type`s
  (`feature_start`, `wave_proceed`, `quality_gate`, `block`), spread across
  `status` (`executed` ×2, `partial` ×1, `blocked` ×1).
- `governance/G-D-20260101-00{1..4}.json` — 4 reports, one per decision,
  covering all three `verdict`s (`agree` ×2, `challenge` ×1, `escalate` ×1).
- `state.json` — 8 run entries (one `t800` + one `t1000` per decision).
  The `t800` run for `D-20260101-004` carries `exit_code: 2` while
  `D-20260101-004.json` is a fully valid artifact — the AC3 fixture proving
  disk is ground truth, not `exit_code`.
- `malformed/D-bad.json` — intentionally invalid JSON (loader skip-test
  input only; excluded from the parse check and from all KPI counts).

## Per-decision raw values

| decision_id | type | status | options | actions | t800 latency (s) |
|---|---|---|---|---|---|
| D-20260101-001 | feature_start | executed | 3 | 2 | 120 |
| D-20260101-002 | wave_proceed  | partial  | 2 | 4 | 180 |
| D-20260101-003 | quality_gate  | blocked  | 1 | 3 | 240 |
| D-20260101-004 | block         | executed | 4 | 3 | 120 |

t800 latency = `finished_at − started_at` of the matching `t800` run
(joined by decision id appearing in `run.task`).

## Per-governance raw values

| decision_id | verdict | confidence | blind_spots | risks | biases fired | decision→governance latency (s) |
|---|---|---|---|---|---|---|
| D-20260101-001 | agree     | 1.0 | 2 | 1 | sunk_cost | 60 |
| D-20260101-002 | agree     | 0.8 | 2 | 3 | anchoring, scope_creep | 60 |
| D-20260101-003 | challenge | 0.6 | 2 | 2 | optimism | 60 |
| D-20260101-004 | escalate  | 0.4 | 2 | 2 | sunk_cost, recency | 60 |

decision→governance latency = `t1000.finished_at − t800.finished_at` for the
same decision id.

## Expected `GandalfKpis`

| field | value |
|---|---|
| `total_decisions` | `4` |
| `avg_latency_secs` | `165.0`  ((120+180+240+120)/4) |
| `min_latency_secs` | `120` |
| `avg_options_considered` | `2.5`  ((3+2+1+4)/4) |
| `min_options_considered` | `1` |
| `type_distribution` | `{ feature_start: 1, wave_proceed: 1, quality_gate: 1, block: 1 }` |
| `status_distribution` | `{ executed: 2, partial: 1, blocked: 1 }` |
| `avg_actions_per_decision` | `3.0`  ((2+4+3+3)/4) |

## Expected `SarumanKpis`

| field | value |
|---|---|
| `total_reviews` | `4` |
| `verdict_distribution` | `{ agree: 2, challenge: 1, escalate: 1 }` |
| `verdict_rates` | `{ agree: 0.5, challenge: 0.25, escalate: 0.25 }` |
| `bias_frequency` | `{ sunk_cost: 2, anchoring: 1, scope_creep: 1, optimism: 1, recency: 1 }` |
| `avg_confidence` | `0.7`  ((1.0+0.8+0.6+0.4)/4) |
| `avg_blind_spots` | `2.0`  (2 each, 8/4) |
| `avg_risks` | `2.0`  ((1+3+2+2)/4) |
| `avg_decision_to_governance_latency_secs` | `60.0`  (60 each) |

## Expected `LoopHealthKpis`

| field | value |
|---|---|
| `challenge_round_trips` | `1` |
| `blocking_escalations` | `1` |
| `auto_reviewed_pct` | `1.0`  (all 4 governed decisions have exactly one `t1000` run each — no later distinct re-review, so all count as auto under the documented heuristic) |
| `decisions_without_governance` | `0` |

## Loader counts (`metaSources.test.ts`)

| loader | expected count |
|---|---|
| `loadDecisions(fixtures/meta/decisions)` | `4` |
| `loadGovernance(fixtures/meta/governance)` | `4` |
| `loadRunState(fixtures/meta/state.json)` | `8` (4 `t800` + 4 `t1000`) |

`malformed/D-bad.json` must be skipped (with a `console.warn`), not thrown,
and must not appear in any of the counts above. The `t800` run for
`D-20260101-004` (`exit_code: 2`) must still be loaded and its matching
`D-20260101-004.json` artifact must still be counted by
`computeMetaMetrics` — the single most important assertion in this corpus
(AC3).
