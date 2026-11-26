# ADR-0008: Autonomous Pipeline Execution with Signal-Based Control

**Status:** Accepted
**Date:** 2026-11-26
**Feature:** F29B

## Context

The pipeline previously required the `/create-feature` slash command to
stay alive and orchestrate every stage inline. This had several drawbacks:

- It tied up a Claude session for the entire pipeline duration, consuming
  tokens even during idle waits between stages.
- There was no way to pause and resume if the token budget ran low --
  a depleted budget would force the session to end, losing pipeline state.
- Negotiation between Handler and GateKeeper was limited to a single
  round of challenge, which was insufficient for complex decisions where
  iterative refinement was needed.
- No external observability -- the operator had no way to check pipeline
  progress, pause, or cancel without entering the Claude session.

## Decision

1. **Extract pipeline execution** into `bin/didio-run-pipeline.sh`, which
   orchestrates all 8 stages (Handler gate, Architect, Readiness, TEA,
   Waves, TechLead, QA, Post-review) in sequence with per-stage state
   tracking.

2. **File-based state tracking** via `logs/agents/pipeline-<FXX>.state.json`,
   updated at every stage transition. Contains feature ID, status, current
   stage, completed/remaining stages, wave progress, exit code, and
   pause/resume metadata.

3. **Signal files for pause/resume/cancel** (filesystem as IPC). Signal
   files in `logs/agents/signals/` (`<FXX>.pause`, `<FXX>.resume`,
   `<FXX>.cancel`) are checked between stages and between waves.

4. **Make `/create-feature` a lightweight dispatcher** that writes the
   brief and launches the pipeline. The dispatcher can exit; the pipeline
   continues autonomously.

5. **Configurable multi-round negotiation** via `negotiation.max_rounds`
   (default 3). Each round produces `logs/governance/G-<id>-round-<N>.json`
   with cumulative blind spots and recommendations. A summary
   (`G-<id>-summary.json`) is written after all rounds.

6. **Post-work review gate** after QA, using the same negotiation loop.
   Enabled by default (`negotiation.post_work_review: true`), skippable
   via flag or config.

7. **Token budget monitoring** via `didio-token-monitor.sh`, which checks
   `logs/session-budget.json` and signals pipeline pause when budget is
   depleted.

8. **Control commands** for external observability:
   - `didio pipeline-status` -- list/detail active pipelines
   - `didio pipeline-pause <FXX>` -- create pause signal
   - `didio pipeline-resume <FXX>` -- create resume signal

## Consequences

- Pipelines can survive session disconnects (resume from persisted state).
- Token budget management prevents wasted sessions -- the pipeline pauses
  gracefully and can resume when budget is refreshed.
- Filesystem-based signaling avoids the need for IPC mechanisms, process
  groups, or database backends. Simple and debuggable.
- Multi-round negotiation improves governance quality by allowing
  iterative refinement of Handler decisions.
- Legacy inline mode is preserved as fallback -- projects that do not
  enable `pipeline.autonomous` continue to work as before.
- Additional complexity: 7 new scripts, state management code, and signal
  file lifecycle management.
- Testing requires mock infrastructure for agent spawning (no real agents
  in tests).

## Alternatives considered

- **Database-backed state** (SQLite, Redis) -- Rejected. Adds a
  dependency for a problem that file-based state solves adequately. The
  pipeline is single-writer (one pipeline per feature), so file locking
  is unnecessary.
- **Process signal-based control** (SIGSTOP/SIGCONT) -- Rejected.
  Requires the pipeline process to be running. File-based signals work
  even when the pipeline is not currently active (e.g., paused and
  waiting for resume).
- **Unlimited negotiation rounds** -- Rejected. Without a cap, adversarial
  or confused agents could loop indefinitely. The configurable max_rounds
  with auto-escalation provides a safety net.
