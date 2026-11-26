# ADR-0011: DOB Benchmark Suite + BMAD Purge Completion

**Status:** Accepted
**Date:** 2026-11-26
**Feature:** F33

## Context

### DOB Benchmark

The claude-didio-config framework orchestrates multi-agent pipelines but had
no objective way to measure orchestration quality across configurations, models,
or framework versions. Decisions about model selection, parallelism settings,
and prompt structures were based on subjective observation rather than data.

Existing benchmarks (F03 caching, F06 token footprint) measured narrow
aspects. A comprehensive, multi-dimensional benchmark was needed.

### BMAD Purge

F27 introduced BMAD methodology integration with dedicated commands and
test files. F29A (corporate rename) deleted 63 operational bmad-prefixed
files but left 5 files with BMAD references in operational code and 4 F27
test files that test now-nonexistent commands.

## Decision

### DOB Benchmark

We adopt a 12-dimension benchmark framework called DOB (Didio Orchestrator
Benchmark) with the following design decisions:

1. **12 dimensions** — covers the full pipeline lifecycle from task decomposition
   through rework rate. Dimensions were chosen to be independently measurable
   and collectively exhaustive for orchestration quality.

2. **K=3 runs** — balances statistical confidence (mean + stddev) against
   token cost. Configurable via `dob.k`.

3. **Offline-first (synthetic fixtures)** — V0 uses pre-computed metrics in
   fixture files rather than executing live pipelines. This enables fast
   iteration on the benchmark tooling itself without consuming tokens.

4. **File-based results** — all metrics stored as JSON files under
   `logs/dob-results/`. Git-friendly, inspectable, diffable.

5. **Separated runner/scorer/regression** — three independent scripts following
   Unix philosophy. Each can be used standalone or composed in CI.

6. **Regression gate** — `dob-regression` exits non-zero when any dimension
   degrades beyond a configurable threshold (default 10%). Designed for CI
   integration.

### BMAD Purge

We complete the BMAD cleanup by:
- Removing references from 5 operational files (tea.md prompts, didio.md menus)
- Deleting 4 F27 test files that test nonexistent commands
- Preserving 4 historical/documentation files as reference

## Consequences

### Positive
- Objective quality measurement enables data-driven decisions
- Regression gate prevents silent quality degradation
- BMAD cleanup reduces confusion for new contributors
- Fixture-based approach allows benchmarking without token cost

### Negative
- V0 synthetic mode doesn't capture real pipeline behavior (addressed in V1)
- 12 dimensions require manual scoring until live metrics collection exists
- Equal weighting (V0) may not reflect actual importance priorities

### Risks
- Synthetic scores may not correlate with live performance
- Mitigation: V1 will collect metrics from actual JSONL logs

## Alternatives Considered

1. **Single aggregate score** — rejected; loses dimensional visibility
2. **Live-only benchmarks** — rejected; too expensive for rapid iteration
3. **K=1 (no repetition)** — rejected; no variance information
4. **Keep BMAD references** — rejected; causes confusion, references
   nonexistent files
