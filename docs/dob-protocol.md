# DOB Protocol — Didio Orchestrator Benchmark

## Purpose

DOB is a benchmark framework for objectively comparing agent orchestration
frameworks and LLM models. It measures 12 dimensions of orchestrator quality
with K=3 runs per configuration for statistical confidence.

DOB answers: "Is framework/model A better than framework/model B for
multi-agent orchestration, and by how much?"

## Dimensions

| # | ID | Name | What it measures |
|---|---|---|---|
| 1 | `task_decomposition` | Task Decomposition Quality | Granularity, independence, completeness of Architect output |
| 2 | `parallel_efficiency` | Parallel Execution Efficiency | Wave utilization, idle time, parallelism ratio |
| 3 | `context_isolation` | Context Isolation | Cross-agent contamination rate |
| 4 | `token_efficiency` | Token Efficiency | Tokens per delivered LOC |
| 5 | `test_coverage_delta` | Test Coverage Delta | Coverage improvement before vs after feature |
| 6 | `diagram_accuracy` | Diagram Accuracy | Diagrams match implementation |
| 7 | `guardrail_compliance` | Guardrail Compliance | Security rules followed |
| 8 | `recovery_resilience` | Recovery Resilience | Rate-limit and failure recovery |
| 9 | `learning_retention` | Learning Retention | Agent-learnings applied correctly |
| 10 | `pipeline_autonomy` | Pipeline Autonomy | Human interventions needed |
| 11 | `time_to_feature` | Time to Feature | Wall-clock excluding rate-limit waits |
| 12 | `rework_rate` | Rework Rate | TechLead/QA rejections per feature |

Full definitions with rubrics: `docs/dob-dimensions.json`.

## Scoring

- Each dimension: **0-10 integer scale**
- Weight: 1.0 per dimension (V0 — equal weighting)
- Overall score: sum of weighted scores (max 120.0 for V0)
- Mean and stddev computed across K runs per dimension

## Running a Benchmark

```bash
# Run with default K from config (default: 3)
didio dob-run --fixture example

# Override K
didio dob-run --fixture example --k 5

# Score the results
didio dob-score logs/dob-results/example/<timestamp>

# Compare against baseline
didio dob-regression logs/dob-results/baseline/summary.json logs/dob-results/current/summary.json
```

## Fixture Format

Fixtures are JSON files in `tests/dob-fixtures/`:

```json
{
  "name": "example",
  "description": "Description of the benchmark scenario",
  "version": "1.0.0",
  "metrics": {
    "task_decomposition": { "values": [7, 8, 7] },
    "parallel_efficiency": { "values": [6, 7, 6] },
    ...
  }
}
```

**V0 (synthetic mode):** Fixtures provide pre-computed metric values. The
runner reads the i-th value from each dimension's `values` array for run i.

**V1+ (live mode):** Fixtures will define a feature scenario; the runner will
execute the full pipeline and collect metrics from JSONL logs.

## Results Structure

```
logs/dob-results/<fixture>/<timestamp>/
  run-1/metrics.json    # per-run raw metrics
  run-2/metrics.json
  run-3/metrics.json
  summary.json          # aggregated by dob-score
```

## Regression Gate

```bash
didio dob-regression <baseline.json> <current.json> [--threshold 10]
```

- **PASS** (exit 0): no dimension degraded beyond threshold
- **FAIL** (exit 1): at least one dimension degraded beyond threshold
- **ERROR** (exit 2): invalid input

A dimension "regresses" when:
`(current_mean - baseline_mean) / baseline_mean * 100 < -threshold_pct`

Default threshold: 10% (configurable in `didio.config.json` or via `--threshold`).

## CI Integration

```yaml
# Example: GitHub Actions
- name: Run DOB benchmark
  run: didio dob-run --fixture baseline-v1 --k 3

- name: Score results
  run: didio dob-score logs/dob-results/baseline-v1/latest

- name: Regression check
  run: didio dob-regression baseline.json logs/dob-results/baseline-v1/latest/summary.json
```

## K Value Rationale

K=3 balances statistical confidence against cost:
- K=1: no variance information, unreliable
- K=3: enough for mean + stddev, catches outliers
- K=5+: diminishing returns for synthetic fixtures

For live benchmarks (V1+), K=3 remains the minimum. Higher K values
recommended when comparing models with high variance.

## Configuration

In `didio.config.json`:

```json
"dob": {
  "enabled": false,
  "k": 3,
  "fixtures_dir": "tests/dob-fixtures",
  "results_dir": "logs/dob-results",
  "dimensions_schema": "docs/dob-dimensions.json",
  "regression": {
    "threshold_pct": 10,
    "block_on_regression": true
  }
}
```
