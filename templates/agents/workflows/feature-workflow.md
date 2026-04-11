# Feature Workflow — {{PROJECT_NAME}}

## Pipeline

```
/create-feature
  ↓
Architect generates tasks
  - Minimal, independent tasks grouped in parallel Waves
  - Wave 0 reserved for setup/permissions
  - Each task includes: objective, impl details, acceptance criteria,
    test scenarios, diagrams
  ↓
didio run-wave <FXX> 0        # setup in parallel
  ↓
didio run-wave <FXX> 1..N     # features in parallel
  ↓
Developer implements each task in a clean bash (via spawn-agent)
  - Stack rules from CLAUDE.md
  - Tests mandatory (happy, edge, error, boundary)
  - Diagrams updated
  ↓
Tech Lead reviews
  - Architecture, code quality, test coverage, diagram accuracy
  - Rejects if gaps found
  ↓
QA validates
  - Runs full test suite
  - Fills missing test gaps
  - Exercises the feature for real (browser / curl / harness)
  - Diagrams reflect reality
```

## Testing Gate

**No Wave advances without passing tests.**

## Diagram Gate

**No feature is complete without diagrams in sync with implementation.**

## Wave 0 Gate

**Wave 0 must front-load everything the later Waves need** (permissions,
dependencies, scaffolding) so Waves 1..N run unattended in parallel.
