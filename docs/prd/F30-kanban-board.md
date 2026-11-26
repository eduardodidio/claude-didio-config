# PRD: F30 -- Kanban Board, Governance Dashboard, Action System

**Feature:** F30
**Status:** Delivered
**Date:** 2026-11-26

## Problem Statement

Operators managing the Didio agent pipeline must use terminal commands to
inspect pipeline state, unblock agents, pause/resume features, and review
governance metrics. This requires memorizing CLI subcommands, reading raw
JSON files, and switching between terminal and browser. Common operations
(checking if a feature is blocked, unblocking it, reviewing token budget)
take multiple steps that could be a single click.

## Solution

A three-layer visual system integrated into the Didio Agents Dash:

### Layer 1: Kanban Board

A 5-column board (Backlog, Planning, Running, Review, Done) that
visualizes all features in the pipeline. Each feature is a card showing:
- Feature ID and current phase
- Progress bar with task count
- Flag indicator dots (color-coded by severity)
- Blocked badge overlay

Cards are automatically placed in columns based on:
1. Running agent role (architect = Planning, developer = Running,
   qa/reviewer = Review)
2. Progress percentage fallback heuristic
3. 100% completion = Done

Clicking a card opens a detail dialog with full flag list, task trail,
and suggested actions.

### Layer 2: Zero-Prompt Action System

Operators can click buttons to dispatch actions without typing commands:
- **Unblock** -- resolve a blocked flag
- **Approve** -- dismiss a flag / approve a review gate
- **Skip** -- skip a blocked task (destructive, requires confirmation)
- **Pause** -- pause a running pipeline
- **Resume** -- resume a paused pipeline
- **Cancel** -- cancel a feature (destructive, requires confirmation)

Actions are written as JSON files to `logs/agents/actions/`. A background
listener (`didio action-listener`) polls this directory and executes the
corresponding operations (resolve flags, write signal files, etc.).

### Layer 3: Governance Dashboard

A dedicated view showing:
- **Active Pipelines** table with phase, wave, tasks, progress, token
  budget, and flag count per feature
- **Token Budget** summary with global and per-feature breakdown,
  warning indicators when usage exceeds 80%
- **Flag Analytics** with total/active/resolved/critical counts,
  distribution by severity and type
- **Decision History** showing Handler and GateKeeper activity metrics

### Supporting Infrastructure

- **Flag library** (`didio-flags-lib.sh`): shell functions for agents to
  raise/resolve flags programmatically
- **Shared learnings protocol**: JSON schema + export/import scripts for
  cross-project knowledge sharing
- **Pipeline orchestrator** (`didio-run-pipeline.sh`): full autonomous
  pipeline with pause/resume/cancel support

## Success Metrics

- Zero terminal commands needed for: checking pipeline status, unblocking
  a feature, pausing/resuming a pipeline, reviewing token budget
- All flag operations visible within 2 seconds of creation (polling)
- Action processing latency under 5 seconds (listener poll interval)

## Out of Scope

- Drag-and-drop card reordering (future enhancement)
- WebSocket real-time updates (polling is sufficient for now)
- Multi-user collaboration (single operator assumed)
- Persistent storage (all state is file-based, ephemeral per session)

## Technical References

- Architecture: `docs/diagrams/F30-architecture.mmd`
- User journey: `docs/diagrams/F30-journey.mmd`
- ADR: `docs/adr/0008-kanban-board-file-based-actions.md`
- Flag schema: `schemas/flag.schema.json`
- Action schema: `schemas/action.schema.json`
- Shared learning schema: `schemas/shared-learning.schema.json`
