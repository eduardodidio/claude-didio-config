# F10 Readiness Fixtures

Five synthetic mini-features exercising each of the 5 readiness checks.

| Fixture        | Expected verdict | Check triggered |
|----------------|------------------|-----------------|
| `ready/`       | READY            | all 5 pass      |
| `missing-ac/`  | BLOCKED          | Check 1 — AC4 uncovered |
| `file-collision/` | BLOCKED       | Check 3 — src/foo.ts in T02 + T03 (same Wave) |
| `no-testing/`  | BLOCKED          | Check 5 — T03 has `_TODO_` in Testing |
| `bad-wave0/`   | BLOCKED          | Check 4 — Wave 1 needs tests/new-dir/ but Wave 0 silent |

## Run all fixtures

```bash
bash tests/F10-readiness-smoke.sh
```

Cost: ~3 min (5 × ~30 s claude calls via `didio spawn-agent readiness`).
Runner exits 0 if all verdicts match; exits 1 on any mismatch.
