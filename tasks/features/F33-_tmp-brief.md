# F33 — DOB Benchmark Suite + BMAD Purge

## Scope

Two deliverables in one feature:

### 1. DOB Benchmark Suite

Create a benchmark framework for objectively comparing agent orchestration
frameworks (and LLM models). The DOB (Didio Orchestrator Benchmark) uses
12 evaluation dimensions with K=3 runs per configuration for statistical
confidence.

**12 Dimensions:**
1. Task decomposition quality (granularity, independence, completeness)
2. Parallel execution efficiency (wave utilization, idle time)
3. Context isolation (cross-agent contamination rate)
4. Token efficiency (tokens per delivered LOC)
5. Test coverage delta (before vs after feature)
6. Diagram accuracy (diagrams match implementation)
7. Guardrail compliance (security rules followed)
8. Recovery resilience (rate-limit, failure recovery)
9. Learning retention (agent-learnings applied correctly)
10. Pipeline autonomy (human interventions needed)
11. Time to feature (wall-clock, excluding rate-limit waits)
12. Rework rate (TechLead/QA rejections per feature)

**Deliverables:**
- Fixture definitions (JSON schema for benchmark scenarios)
- Runner script (`bin/didio-dob-runner.sh`) that executes K runs
- Scorer script (`bin/didio-dob-scorer.sh`) that aggregates results
- Protocol documentation (`docs/dob-protocol.md`)
- Regression gate (`bin/didio-dob-regression.sh`) that blocks MRs degrading scores
- Smoke test to validate the benchmark pipeline end-to-end
- ADR for DOB benchmark design decisions

### 2. BMAD Purge

Remove all BMAD-prefixed operational artifacts that were superseded by the
corporate standardization (F29A). The BMAD methodology was an inspiration,
but the operational code now uses neutral names (Handler, GateKeeper, etc.).

**Scope:**
- Delete ~51 bmad-prefixed files from `skills/`, `templates/commands/`,
  `templates/.claude/commands/`
- Edit ~12 files to remove bmad references from operational artifacts
- Keep historical/documentation files (`bmad-integration-plan.md`, comparison docs)
  as reference only
- README gets a brief credit line (already present in "Inspirations" section)
- Verify no runtime code depends on deleted files

### Acceptance Criteria (feature-level)

- [ ] `didio dob-run --fixture <name> --k 3` executes benchmark and produces scored results
- [ ] 12 dimensions defined in JSON schema with clear scoring rubrics
- [ ] `didio dob-score <results-dir>` aggregates K runs into a single report
- [ ] `didio dob-regression <baseline> <current>` exits non-zero if any dimension degrades beyond threshold
- [ ] Smoke test validates the full benchmark pipeline
- [ ] All bmad-prefixed operational files deleted
- [ ] No runtime breakage after purge (all existing tests pass)
- [ ] README updated with DOB benchmark section and BMAD purge note
- [ ] ADR documenting DOB design and BMAD purge rationale
- [ ] At least 2 Mermaid diagrams (architecture + user journey)
