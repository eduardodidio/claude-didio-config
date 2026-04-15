# F03 Benchmark Results

**Date:** 2026-04-14  
**Host:** macOS Darwin 25.3.0 (Apple Silicon)  
**Python:** 3.x  
**Workspace:** 6 fake features × 40 tasks/feature (~25-line READMEs)

## Summary

The mtime-based README cache in `_planned_tasks` (added in F03-T03) delivers
a **>= 2× speedup** on repeated calls within the same process — the core
guarantee the cache was designed to provide.

## 1. `_planned_tasks` benchmarks (N=200 iterations)

This is the primary metric: the cache eliminates the README file-open,
readline × N, and glob syscalls on every warm hit.

| Feature | Cold (ms) | Warm (ms) | Ratio | Result |
|---------|-----------|-----------|-------|--------|
| F01     | 10.27     | 4.50      | 0.439 | OK     |
| F02     |  9.23     | 4.14      | 0.449 | OK     |
| F03     |  8.74     | 3.96      | 0.453 | OK     |
| F04     |  8.18     | 3.92      | 0.480 | OK     |
| F05     |  8.14     | 3.72      | 0.457 | OK     |
| F06     |  8.19     | 3.75      | 0.457 | OK     |

**All ratios < 0.50** — warm cache is under 50% of cold, confirming the
acceptance criterion.

## 2. `compute_feature` benchmarks (N=100 iterations)

`compute_feature` calls `_planned_tasks` internally but also iterates over
the full agents list and builds the task trail. This non-cached work raises
the warm/cold ratio compared to the pure `_planned_tasks` benchmark.

| Feature | Cold (ms) | Warm (ms) | Ratio |
|---------|-----------|-----------|-------|
| F01     | 4.60      | 2.52      | 0.548 |
| F02     | 4.83      | 2.49      | 0.516 |
| F03     | 4.66      | 2.51      | 0.538 |
| F04     | 5.04      | 2.53      | 0.503 |
| F05     | 4.69      | 2.52      | 0.537 |
| F06     | 4.67      | 2.53      | 0.541 |

Warm calls are still ~46–50% faster end-to-end despite the non-cached
agent iteration overhead.

## 3. All-features benchmarks (6 features × 20 outer iterations)

This simulates the watcher loop processing every known feature per tick.

| Mode        | Total time (ms) | Ratio |
|-------------|-----------------|-------|
| Cache cold  | 5.80            | —     |
| Cache warm  | 3.13            | 0.539 |

~46% reduction in all-features loop time.

## Interpretation

- **The cache saves the file-read path** (`glob`, `open`, `f.readline` × N,
  regex scan). On warm hits only `os.path.getmtime` is called.
- **The `compute_feature` ratio is higher (≈0.54)** because agent list
  iteration is constant regardless of cache state. This is expected and
  acceptable; agent lists are small (one file per task run) compared to
  the README parse cost at scale.
- **At >= 5 features with realistic README sizes (40+ tasks)**, the cache
  consistently delivers > 2× speedup on the README parse path, satisfying
  the F03 global acceptance criterion (criterion 1).

## No-op guard

Verified by `F03-integration-test.sh`:
- `state.json` mtime remains stable across idle ticks (no `.meta.json`
  changes) — the no-op guard correctly suppresses writes.
- `state.json` mtime updates within ~1 s of a new `.meta.json` being
  added — real changes propagate as expected.
