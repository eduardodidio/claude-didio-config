# ADR 001 — Shared Status Constants: TypeScript ↔ Python

- **Date**: 2026-04-14
- **Status**: Rejected
- **Deciders**: Framework maintainers

---

## Context

The framework has two execution contexts that each track "status" values:

| Source | Location | Values |
|--------|----------|--------|
| Python (progress tracker) | `bin/didio-progress.py` lines 22–25 | `completed`, `running`, `failed`, `planned` |
| TypeScript `TrailStatus` | `dashboard/src/lib/types.ts` line 26 | `completed`, `running`, `failed`, `planned` |
| TypeScript `AgentStatus` | `dashboard/src/lib/types.ts` line 1 | `running`, `completed`, `failed`, `blocked` |

At first glance, `TrailStatus` and the Python constants appear to be the same
set. This raised the question: should we maintain a single canonical
`shared/status.json` to prevent the two sources from drifting apart?

The proposed implementation would be:

```json
{
  "trail_status": ["completed", "running", "failed", "planned"],
  "agent_status": ["running", "completed", "failed", "blocked"]
}
```

Python would load this at import time via `json.load`; TypeScript would
derive its union types via a build-time assertion or code-gen step.

---

## Decision

**Rejected.** We will keep separate, hardcoded definitions in each language.

---

## Reasoning

### 1. The status sets are semantically distinct, not accidentally divergent

`TrailStatus` and `AgentStatus` model *different concepts*:

- **`TrailStatus`** represents the lifecycle of a *task* in a feature plan.
  `planned` is a valid task state ("this task hasn't been started yet");
  `blocked` is not a task state in this model.

- **`AgentStatus`** represents the execution state of an *agent run*.
  `blocked` is a valid agent state ("agent could not proceed"); `planned`
  is not an agent-execution state.

- **Python `STATUS_*`** tracks progress for the progress-display subsystem,
  which operates on the *task* view — matching `TrailStatus`, not
  `AgentStatus`.

These sets will intentionally diverge further as the framework evolves (e.g.,
`AgentStatus` may add `'timeout'` without any corresponding `TrailStatus`
change). Forcing them into a shared file creates false coupling.

### 2. The overlap is coincidental, not a contract

`TrailStatus` and the Python constants happen to share the same four values
today. That coincidence does not imply they should be governed by the same
source of truth. The Python script and the TypeScript trail component
independently arrived at the same four states because those are the natural
planning lifecycle states — not because they share a specification.

### 3. Cross-language sharing adds non-trivial operational complexity

Making Python load a JSON file at import time requires:
- Reliable relative-path resolution (the script is invoked from varying
  working directories).
- A hard failure if the file is missing — falling back silently would be
  worse than hardcoding.
- CI plumbing to ensure the JSON is present wherever the script runs.

Making TypeScript derive union types from a JSON file requires either:
- A build-time codegen step (new tooling, new failure mode).
- A runtime assertion (loses compile-time type safety, the main value of
  TypeScript enums/unions).

Neither option is zero-cost, and both introduce a new category of failure
(file-not-found) that does not exist today.

### 4. Drift risk is near zero

Status constants in a workflow framework are among the most stable values in
a codebase. Adding or removing a status is a breaking change by definition —
it requires updating every switch/match statement that consumes it. The
discipline required to update two files (one Python constant block, one TS
union type) is no greater than the discipline required to update one JSON
file, and the compiler/linter already enforces exhaustiveness in TypeScript.

### 5. The shared-JSON approach still requires per-language knowledge

Even with `shared/status.json`, each consumer must know *which key* to use:
Python reads `trail_status`; the `TrailStatus` union reads `trail_status`;
the `AgentStatus` union reads `agent_status`. The shared file does not
eliminate the need to understand which concept each side models — it only
centralises the raw string arrays, which are stable and short.

---

## Consequences

### Positive

- Zero new tooling or file-discovery logic.
- No new category of runtime failure (missing JSON).
- TypeScript union types remain compile-time checked.
- Each codebase continues to use idiomatic patterns (Python constants,
  TypeScript union literals).

### Negative / Trade-offs

- If a status value is renamed, two files must be updated instead of one.
  Accepted: exhaustiveness checking in TypeScript and `grep` make this
  discoverable. The status names are stable.

### No code changes required

Because this decision is "reject", no files outside this ADR need to be
modified. The existing definitions in `bin/didio-progress.py` and
`dashboard/src/lib/types.ts` remain the sources of truth for their
respective domains.
