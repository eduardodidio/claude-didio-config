# ADR-0019: Squad Orchestrator

## Status

Accepted

**Date:** 2026-11-27
**Feature:** F41

## Context

Bravo (CI/CD), Charlie (monitoring), and Delta (security) run independently.
Operators must run three commands to get a complete picture. Cross-scanner
insights (e.g., failed pipeline + dangerous shell = elevated risk) are lost.

## Decision

### Single CLI entry point

`didio squad scan` runs all enabled scanners in sequence, correlates findings,
and produces a combined report. Individual scanners remain available via their
own CLIs for targeted scanning.

### Cross-scanner correlation

5 compound patterns detect risks that no single scanner can see:
1. pipeline_security_compound (Bravo + Delta)
2. framework_degradation (Charlie internal)
3. secret_exposure (Delta internal)
4. operational_stress (Bravo + Charlie + Delta)
5. unprotected_operations (Delta internal)

### Per-scanner enable/disable

Each scanner respects its `meta_agents.blackhawk_<name>.enabled` config flag.
Disabled scanners show as "disabled/unavailable" in the report.

## Consequences

### Positive
- One command for complete health picture
- Cross-scanner correlation catches compound risks
- Reuses existing scanner libraries (no code duplication)

### Negative
- Sequential execution (not parallel) — acceptable for file-based scanning
- Correlation patterns are hardcoded (not configurable)
