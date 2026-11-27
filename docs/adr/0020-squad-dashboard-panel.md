# ADR-0020: Squad Dashboard Panel

## Status

Accepted

**Date:** 2026-11-27
**Feature:** F42

## Context

The squad orchestrator (F41) produces JSON reports read via CLI. Operators
need a visual panel in the desktop app to see squad health at a glance.

## Decision

### 5th tab in Black Hawk Desktop

Added a "Squad" tab alongside Chat, Board, Alerts, and Config. The tab
shows per-scanner status (Bravo/Charlie/Delta) with color-coded indicators,
correlation alerts, and a scan trigger button.

### Frontend-only polling

The hook `useSquadHealth` reads the latest squad report via `getSquadReport()`
Tauri bridge call, polling every 10 seconds. No new Rust watcher needed —
the existing file watcher infrastructure can be extended later.

### Scan trigger via executeAction

The "Run Scan" button calls `triggerSquadScan()` which invokes
`didio squad scan --once` via the existing `execute_action` Tauri command.
No new Rust command needed.

## Consequences

### Positive
- Zero new Rust code — reuses existing bridge patterns
- Visual feedback for squad health without terminal
- Scan trigger from the UI closes the feedback loop

### Negative
- Polling-based (not real-time push) — 10s latency
- `getSquadReport` Rust command not yet implemented — needs backend wiring
  (same pattern as F34 `get_board_state`)
