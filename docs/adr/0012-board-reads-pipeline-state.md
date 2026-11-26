# ADR-0012: Board Reads Pipeline State Files Directly

## Status

Accepted

**Date:** 2026-11-26
**Feature:** F34

## Context

The Black Hawk Desktop board component (delivered in F32) was designed to
display feature pipeline status in a compact Kanban view. However, the
initial implementation read from nonexistent `status.json` files under
`tasks/features/*/`, which never existed in the project.

Meanwhile, the pipeline automation system (F29B) already writes rich state
files to `logs/agents/pipeline-*.state.json` via `didio-run-pipeline.sh`.
These files contain stage, status, progress percentage, task counts, and
timing information -- everything the board needs to render accurately.

The flags system (`didio-flags-lib.sh`) writes flag files to
`logs/agents/flags/`, but the desktop alerts component was reading from the
incorrect path `logs/flags/`.

## Decision

The board component reads pipeline state files directly from
`logs/agents/pipeline-*.state.json` instead of maintaining a separate board
data format. The `get_board_state` Tauri command parses these files and
returns structured data to the React frontend.

Similarly, the alerts component reads flags from the correct path
`logs/agents/flags/` as written by `didio-flags-lib.sh`.

The file watcher (`watcher.rs`) monitors both directories and emits events
to the frontend when changes are detected, enabling real-time updates
without polling.

## Consequences

### Positive

- **Single source of truth** -- no duplication of pipeline state; the board
  always reflects the actual pipeline status
- **Real-time updates** -- file watcher emits events on disk changes,
  providing instant board/alert updates
- **Zero additional infrastructure** -- no database, no API server, no
  message broker; just files on disk
- **Pipeline-independent** -- board works whether the pipeline is running
  locally, in CI, or was run hours ago (state files persist)

### Negative

- **Schema coupling** -- the board parser is coupled to the pipeline state
  file schema defined by `didio-run-pipeline.sh`. Any change to the state
  schema requires a corresponding update to the Rust `get_board_state`
  parser in `commands.rs`
- **File system dependency** -- the board cannot function without access to
  `logs/agents/` on the local file system
- **No historical view** -- state files represent current state only; there
  is no built-in timeline or history of pipeline runs (logs serve that
  purpose separately)

### Risks

- Pipeline state schema evolves without updating the board parser --
  mitigated by the test suite validating parser against fixture state files
- Large number of state files in `logs/agents/` could slow the watcher --
  mitigated by glob-based filtering (only `pipeline-*.state.json` files)

## Alternatives Considered

1. **Separate board database (SQLite)** -- rejected; adds complexity and a
   second source of truth that must stay in sync
2. **Board writes its own status files** -- rejected; duplicates data
   already available in pipeline state
3. **API polling from frontend** -- rejected; file watcher provides
   lower-latency updates with less overhead
4. **Shared JSON schema with validation** -- considered for V1; would add a
   JSON Schema file that both pipeline and board validate against
