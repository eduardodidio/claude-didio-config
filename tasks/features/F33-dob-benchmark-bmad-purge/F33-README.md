# F33 — DOB Benchmark Suite + BMAD Purge

## Goal

Deliver the DOB (Didio Orchestrator Benchmark) framework for objectively
comparing agent orchestration frameworks and LLM models across 12 evaluation
dimensions with K=3 runs per configuration. Simultaneously, complete the BMAD
cleanup by removing the 5 remaining reference files and 4 obsolete F27 test
files, and editing the ~5 files that still contain operational BMAD references.

## Architecture Impact

- **Config layer** (`didio.config.json`): new `dob` block with fixture paths,
  K value, regression thresholds
- **CLI layer** (`bin/didio`): 3 new subcommands (`dob-run`, `dob-score`,
  `dob-regression`)
- **Scripts** (`bin/`): 3 new shell scripts
- **Schema** (`docs/`): DOB dimension schema + protocol doc
- **Tests** (`tests/`): DOB smoke test + fixtures
- **Docs** (`docs/adr/`): ADR-0011 for DOB design + BMAD purge rationale
- **Diagrams** (`docs/diagrams/`): F33-architecture.mmd + F33-journey.mmd
- **Cleanup**: edit 5 files to remove BMAD refs, delete 4 F27 test files

## Wave Manifest

- **Wave 0**: F33-T01, F33-T02 (config schema + DOB dimension definitions)
- **Wave 1**: F33-T03, F33-T04, F33-T05, F33-T06 (runner, scorer, regression gate, CLI wiring)
- **Wave 2**: F33-T07, F33-T08 (BMAD purge edits + F27 test cleanup)
- **Wave 3**: F33-T09, F33-T10, F33-T11, F33-T12 (protocol docs, ADR, diagrams, smoke test)
- **Wave 4**: F33-T13, F33-T14, F33-T15 (README update, DOB fixtures, final integration test)

## Dependency Graph

```
T01 (config)    T02 (dimensions schema)
  \                /
   +------+------+
          |
   +------+------+------+
   |      |      |      |
  T03    T04    T05    T06
(runner)(scorer)(regr) (CLI)
   |      |      |      |
   +------+------+------+
          |
     +----+----+
     |         |
    T07       T08
 (bmad edit)(F27 tests)
     |         |
     +----+----+
          |
  +-------+-------+-------+
  |       |       |       |
 T09     T10     T11     T12
(proto) (ADR)  (diagrams)(smoke)
  |       |       |       |
  +-------+-------+-------+
          |
   +------+------+------+
   |      |             |
  T13    T14           T15
(README)(fixtures) (integration)
```

## Global Acceptance Criteria

- [ ] `didio dob-run --fixture <name> --k 3` executes benchmark and produces scored results
- [ ] 12 dimensions defined in JSON schema with clear scoring rubrics (0-10 scale)
- [ ] `didio dob-score <results-dir>` aggregates K runs into a single report
- [ ] `didio dob-regression <baseline> <current>` exits non-zero if any dimension degrades
- [ ] Smoke test validates the full benchmark pipeline with synthetic fixture
- [ ] All residual BMAD operational references removed from code
- [ ] F27 obsolete test files removed
- [ ] No runtime breakage after cleanup (existing tests pass)
- [ ] README updated with DOB benchmark section
- [ ] ADR-0011 documenting DOB design and BMAD purge rationale
- [ ] F33-architecture.mmd + F33-journey.mmd in docs/diagrams/

## Diagrams

- `docs/diagrams/F33-architecture.mmd` — DOB runner/scorer/regression data flow
- `docs/diagrams/F33-journey.mmd` — operator journey: run benchmark -> review scores -> PR gate
