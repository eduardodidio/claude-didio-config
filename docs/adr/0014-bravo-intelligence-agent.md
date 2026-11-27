# ADR-0014: Black Hawk Bravo Intelligence Agent

## Status

Accepted

**Date:** 2026-11-27
**Feature:** F36

## Context

The Black Hawk squad (F31) established Alpha as the strategic command agent
handling triage, promotion, and governance monitoring. As the framework grew,
the volume of structured data (pipeline states, flags, token budgets, decisions,
governance reviews) exceeded what Alpha's governance monitor could passively
track. We needed a dedicated intelligence agent focused purely on scanning and
reporting — without the strategic decision-making responsibilities that Alpha
carries.

## Decision

### 1. Bravo as a passive scanner, not an active orchestrator

Bravo is **read-only**: it scans structured log files and produces intelligence
reports. It never starts pipelines, makes strategic decisions, or modifies the
files it scans. This separation ensures Bravo cannot interfere with pipeline
execution or override Handler/GateKeeper decisions.

### 2. Scanners as bash functions using python3 for JSON parsing

Each scanner is a bash function that delegates JSON parsing and analysis to
inline `python3 -c` scripts. This follows the established pattern from
`bin/didio-blackhawk-promote.sh` (F35) and avoids adding jq as a dependency.
The bash layer manages control flow and variable passing; python3 handles
data processing.

### 3. Report-then-card pattern

Bravo writes a JSON report first, then creates War Room cards based on the
report's findings. This decouples observation from action:
- Reports are always written (even in dry-run mode)
- Card creation can be skipped (dry-run) or fail without losing observations
- Reports serve as an audit trail of what Bravo detected
- Multiple report consumers can read the same data (dashboard, Alpha, operator)

### 4. Card deduplication by title

Before creating a War Room card, Bravo checks for existing cards with the same
title in `incoming` or `triaging` status. This prevents card flooding when Bravo
runs continuously on the same anomalous data. Cards that have been promoted,
deferred, or archived are ignored — if the same anomaly recurs after being
addressed, a new card is appropriate.

### 5. Finding grouping by type

Findings are grouped by anomaly type (e.g., all `stuck_pipeline` findings
become one card, all `stale_flag` findings another). This prevents card noise
when multiple pipelines are stuck simultaneously and matches how operators
think about problems (class of issue, not individual instance).

## Consequences

### Positive

- **Decoupled from Alpha**: Bravo can run independently; Alpha triages Bravo's
  cards through the standard War Room flow
- **Testable with fixtures**: 18 E2E tests validate all scanners with synthetic
  data, no agent spawn needed
- **Non-destructive**: read-only scanning cannot break pipelines or corrupt state
- **Extensible**: new scanners (e.g., JSONL log scanner, test result scanner)
  can be added as new functions without changing the aggregator

### Negative

- **File-based scanning has latency**: Bravo reads snapshots, not real-time
  streams. A pipeline that fails between scans won't be detected until the
  next scan cycle (default: 15 minutes)
- **Overlap with governance monitor**: Some of Bravo's decision scanner
  detections overlap with `lib/blackhawk-governance.sh`. The difference is
  that Bravo reports findings passively (via report JSON) while the governance
  lib actively creates cards. Future: consider consolidating into Bravo as
  the single intelligence source

### Risks

- Card dedup by title is fragile if titles change between versions. Mitigated
  by using a stable `[Bravo] <Finding Type>` title format
- Continuous mode (`--continuous`) runs in a sleep loop without graceful
  shutdown handling. Mitigated by running via systemd/launchd in production
  or via the desktop app's process manager
