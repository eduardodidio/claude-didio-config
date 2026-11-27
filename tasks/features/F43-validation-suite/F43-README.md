# Feature F43 — Comprehensive Validation & Stress Test Suite

**Status:** in-progress
**Owner:** @operator
**PRD:** inline (this is a meta-validation feature)

## Goal

Complete validation of all framework components (F29A-F42) with journey tests,
structural integrity checks, DOB stress testing, and edge case coverage.

## Architecture impact

- `tests/` — new E2E journey tests, stress tests, edge case tests
- `tests/dob-fixtures/` — new stress fixtures
- `schemas/` — potential fixes for validation gaps
- `bin/` — potential fixes for race conditions and structural issues
- `docs/diagrams/` — gap fills for missing diagrams

## Waves

- **Wave 0**: F43-T01 (audit consolidation + structural fixes)
- **Wave 1**: F43-T02, F43-T03, F43-T04 (parallel: journeys, DOB stress, edge cases)
- **Wave 2**: F43-T05 (full suite execution + coverage report)

## Dependency Graph

```
F43-T01 (audit + fixes)
  ├──→ F43-T02 (journey E2E tests)
  ├──→ F43-T03 (DOB stress tests)
  └──→ F43-T04 (edge case tests)
         │
         ↓
       F43-T05 (full suite + report)
```

## Audit Findings Summary

### Critical (from War Room/Board audit)
1. Race condition: Card ID collision on concurrent add
2. Race condition: Feature ID collision on concurrent promote
3. Race condition: Concurrent assess on same card
4. Missing file lock on card JSON writes

### High
5. Assessment parse fragility (regex-based)
6. No schema validation on card add
7. Re-promotion allowed without check
8. Stale pipeline state not detected
9. Config values not validated at startup

### Structural (from integrity + coverage audits)
10. charlie.md and delta.md prompt files MISSING — FIXED
11. ADR-0008 duplicated (kanban + pipeline) — FIXED (renumbered to 0021)
12. ADR-001 non-standard numbering — FIXED (renumbered to 0022)
13. F29A missing both diagrams — FIXED
14. 13 orphaned scripts not in dispatcher (intentional helpers)
15. 40 unused config keys (many are frontend-only or planned)
16. 3 unused schemas (warroom-card, board-status, blackhawk-config)

### Test Coverage (from coverage audit)
17. 13 features with ZERO tests (F02,F04,F05,F17-F21,F26,F29A,F30,F32,F38)
18. 4 different assertion patterns (inconsistent: _pass/_fail, assert_eq, TAP, report)
19. 3 files missing cleanup traps (F13-tea-e2e, F15-pre-tool-unit, F42-squad-dashboard)
20. F35-F42 have incomplete TAP (2 assertions where 10+ expected)
21. ~506 total assertions across 72 test files

### DOB Benchmark (from DOB audit)
22. OPERATIONAL — math correct, no division-by-zero
23. 15 untested edge cases (K variation, out-of-range, threshold boundary)
24. Population stddev (DOB-002) — not sample stddev
25. No range validation [0,10] for dimension values
26. No strict 12-dimension enforcement

## Global acceptance criteria

- [ ] All 4 audit reports consolidated
- [ ] Critical race conditions have tests (even if not fixed — document as known)
- [ ] DOB stress test passes with K=1,3,5 and edge cases
- [ ] All 7 journey flows have E2E tests
- [ ] 10 edge case scenarios tested
- [ ] Full test suite runs with TAP output
- [ ] Coverage report generated (features x dimensions)
- [ ] README updated with F43 delivery note
