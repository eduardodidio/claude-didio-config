# ADR-0015: Knowledge Mesh Cross-Project

## Status

Accepted

**Date:** 2026-11-27
**Feature:** F37

## Context

The second-brain MCP (F06) and learnings sync (F30) established per-project
agent learnings that agents can query before each run. However, each project
operates in isolation — an agent working on project A cannot access patterns
discovered on project B. When the same anti-pattern is discovered independently
on 3 different projects, we waste tokens and time rediscovering instead of
sharing.

The existing `didio-learnings-sync.sh` can export and import between projects,
but requires manual coordination (operator must specify the shared path and run
sync on each project separately). There is no central registry of which projects
exist and no way to query learnings across all projects at once.

## Decision

### 1. User-level mesh registry at `~/.didio/mesh-registry.json`

The registry is stored at the user level (not project level) so it can
reference multiple projects without being embedded in any single project. The
`~/.didio/` directory is the framework's user-level config home.

An env var `DIDIO_MESH_REGISTRY` overrides the path for testing and CI.

### 2. File-based sync using existing export/import scripts

The mesh sync reuses `didio-learnings-export.sh` and `didio-learnings-import.sh`
rather than inventing a new sync mechanism. This is the N-to-N version of the
existing 1-to-1 sync:

1. Export: for each registered project, run the existing export script
2. Import: for each project pair (A, B), import B's export into A
3. Update: record `last_sync` and `learnings_count` in the registry

No new data format was introduced; the shared-learnings JSON schema is reused.

### 3. Cross-project query via direct file scan

Rather than requiring the second-brain MCP for cross-project queries, the
`didio mesh query` command reads `memory/agent-learnings/*.md` files directly
from each registered project's filesystem. This works without MCP, without
network, and without any setup beyond registering the project.

### 4. No cross-project isolation

All projects registered in the mesh can see each other's learnings. There is
no access control or permission model. This is appropriate for a single
developer's portfolio of projects on the same machine. Corporate environments
with separate teams/security domains would need a different architecture
(e.g., MCP-based with per-project auth tokens).

## Consequences

### Positive

- **Zero new dependencies**: reuses existing export/import, reads files directly
- **Incremental**: projects can be registered one at a time
- **Offline**: works without MCP, without network, without services
- **Queryable**: `didio mesh query` enables instant cross-project discovery
- **Testable**: 15 E2E tests with synthetic projects, no real data needed

### Negative

- **No real-time sync**: learnings are shared only when `didio mesh sync` runs
  (or on retro ceremony if `auto_sync_on_retro` is enabled)
- **No conflict resolution**: if two projects learn opposite lessons, both
  persist without reconciliation
- **Path-based**: registry stores absolute paths; moving a project breaks
  the reference (operator must re-register)
- **Same-machine only**: the registry references local filesystem paths;
  cross-machine mesh would require a different transport

### Risks

- Registry corruption if two processes write simultaneously (mitigated by
  the low-frequency access pattern — sync and register are operator-initiated)
- Large portfolios (50+ projects) could make query slow (mitigated by the
  `--limit` flag and the fact that learnings files are small)
