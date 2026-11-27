# ADR-0017: Black Hawk Charlie Monitoring Agent

## Status

Accepted

**Date:** 2026-11-27
**Feature:** F39

## Context

Bravo (F36) handles CI/CD intelligence (pipeline state, flags, tokens,
decisions). But the framework itself lacks observability: how often do agents
succeed? How fast are features shipping? Are learnings accumulating? Is the
watcher running? Charlie fills this gap with framework-level health monitoring.

## Decision

### Follow the Bravo scanner pattern exactly

Charlie uses the same architecture as Bravo: 4 modular scanners, each setting
status + findings variables, feeding into a report writer and card creator.
This consistency means operators learn one pattern for all squad agents.

### Scan .meta.json for agent stats instead of JSONL

Agent JSONL logs are large and varied. The `.meta.json` sidecar files contain
structured summary data (exit_code, duration, role) that's faster to parse
and sufficient for health monitoring.

### Feature velocity via README mtime

Rather than parsing git logs (which requires git operations), Charlie uses
the modification time of `FXX-README.md` files as a proxy for when features
were actively worked on. This is imprecise but fast and dependency-free.

### Watcher liveness via state.json mtime

The dashboard watcher regenerates `logs/agents/state.json` every 1-5 seconds.
If the file is older than 300 seconds, the watcher is likely not running.
This is a simple, zero-overhead liveness check.

## Consequences

### Positive
- Consistent pattern with Bravo — operators and developers learn once
- .meta.json parsing is fast (small files, structured data)
- 12 E2E tests with synthetic fixtures
- Complements Bravo: Bravo = CI/CD health, Charlie = framework health

### Negative
- Feature velocity via mtime is imprecise (file touch != feature shipped)
- No historical trend tracking (each report is a snapshot, not a time series)
- Metrics removed from report JSON to avoid shell argument length issues
