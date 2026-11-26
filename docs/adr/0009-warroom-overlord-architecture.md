# ADR-0009: War Room + Black Hawk Alpha Two-Board Architecture

**Status:** Accepted (updated: renamed Overlord -> Black Hawk Alpha, 2026-11-26)
**Date:** 2026-11-26
**Feature:** F31

> **Rename note:** The strategic agent originally called "Overlord" was
> renamed to "Black Hawk Alpha" as part of the Black Hawk system rebrand.
> The desktop app directory changed from `overlord-desktop/` to
> `blackhawk-desktop/`, CLI commands from `didio overlord` to
> `didio blackhawk`, and config keys from `overlord.*` to `blackhawk.*`.
> The JSON data field `overlord_assessment` on War Room cards is preserved
> for backward compatibility with existing card files.

## Context

The claude-didio-config framework has a well-established Standard Board
(Kanban) for structured pipeline work: features flow through Backlog,
Planning, Running, Review, and Done. However, strategic items -- ideas,
concerns, patterns detected in governance logs, operator brainstorms --
had no structured intake process. They were either lost in chat history,
tracked informally, or forced into the feature pipeline prematurely.

We needed a system that:
1. Captures unstructured strategic items from multiple sources (operator,
   agents, governance monitoring).
2. Provides a triage process that evaluates items against project context
   before they enter the pipeline.
3. Maintains separation between strategic triage and operational execution.
4. Fits the existing file-based, git-friendly architecture.

## Decision

### 1. War Room as a separate board (not merged with Standard Board)

War Room items are unstructured strategic items; the Standard Board is a
structured execution pipeline. Mixing them would add noise to both:
operators would see untriaged ideas alongside running features, and
agents would need to distinguish between actionable tasks and strategic
brainstorms.

The War Room has its own 5-column status model: `incoming`, `triaging`,
`promoted`, `deferred`, `archived`. Only `promoted` cards bridge to the
Standard Board by creating feature stubs in `tasks/features/`.

### 2. File-based data model (JSON files, not database)

Consistent with the existing framework pattern (flags, actions, pipeline
state all use JSON files). Benefits:
- Works without external dependencies (no database, no server).
- Git-friendly for auditing and version control.
- Agents read/write cards with standard file I/O.
- Dashboard aggregates via Vite dev-server plugin (same pattern as
  `flags.json` and `pipeline-state.json`).

Cards live in `logs/warroom/cards/<card_id>.json`. The card ID format
`WR-YYYYMMDD-NNN` provides natural chronological ordering and
human-readable identification.

### 3. Black Hawk Alpha as meta-agent above Handler/GateKeeper

The agent hierarchy before F31:
```
Handler (orchestration) <-> GateKeeper (governance)
  |
Architect -> Developer -> TechLead -> QA
```

Black Hawk Alpha sits above this layer:
```
Black Hawk Alpha (strategic)
  | observes
Handler (orchestration) <-> GateKeeper (governance)
  | directs
Architect -> Developer -> TechLead -> QA
```

Strategic decisions (what to work on, what to defer, what patterns
indicate systemic issues) need a different perspective than operational
orchestration (how to execute a specific feature). Separation of
concerns keeps each agent's prompt focused and its decisions auditable.

### 4. Black Hawk Alpha observes but does not override

Black Hawk Alpha can:
- Read all project knowledge (ADRs, learnings, features, decisions,
  governance logs).
- Assess War Room cards and write recommendations.
- Create new War Room cards when it detects patterns.
- Promote cards to feature stubs.

Black Hawk Alpha cannot:
- Override Handler/GateKeeper decisions.
- Directly modify running pipelines.
- Skip governance gates.

This avoids a single point of failure. Handler and GateKeeper maintain
operational autonomy. If Black Hawk Alpha makes a poor strategic call, the
existing governance layer catches it at execution time.

## Consequences

### Positive

- Clean separation between strategic triage and operational execution.
- Operators have a visual dashboard for all strategic items.
- Governance monitoring creates a feedback loop: patterns in decision
  and governance logs generate new strategic cards automatically.
- File-based model is consistent, auditable, and dependency-free.
- Black Hawk Alpha's observe-not-override design prevents cascading failures.

### Negative

- Two boards to monitor (mitigated by the dashboard showing both).
- Promotion bridge adds a step between idea and execution (intentional:
  ideas should be evaluated before consuming pipeline resources).
- Black Hawk Alpha knowledge gathering reads many files per triage cycle
  (mitigated by batching and caching in the triage script).

### Risks

- War Room could accumulate stale cards if triage is not run regularly.
  Mitigated by configurable `triage_interval` and governance monitoring
  that creates cards for detected patterns.
- Black Hawk Alpha assessment quality depends on the richness of the knowledge
  base. Early in a project's life, assessments may be less informed.

## Alternatives Considered

1. **Merge into Standard Board with a "triage" column** -- Rejected
   because it mixes concerns and adds noise to the operational pipeline.
2. **Database-backed storage** -- Rejected for consistency with the
   file-based architecture and to avoid external dependencies.
3. **Black Hawk Alpha with override authority** -- Rejected to maintain the
   existing governance safety net and avoid single-point-of-failure.
