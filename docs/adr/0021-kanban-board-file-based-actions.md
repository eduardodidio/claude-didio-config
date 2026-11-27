# ADR-0008: Kanban Board File-Based Actions

**Status:** Accepted
**Date:** 2026-11-26
**Feature:** F30

## Context

The Didio Agents Dash needs a Kanban board with operator actions (unblock,
approve, skip, pause, resume, cancel) that control the agent pipeline. The
challenge is enabling dashboard-to-pipeline communication without
introducing a database, websocket server, or other stateful infrastructure.

The existing architecture already uses file-based communication: agents
write JSONL logs, the log watcher produces `state.json`, and the dashboard
polls it. The question is whether to extend this pattern or introduce a
new communication channel.

Additionally, the action listener must work on Windows Git Bash (MINGW64)
where `inotify` / `fswatch` are unavailable.

## Decision

1. **File-based action dispatch**: The dashboard writes action JSON files
   to `logs/agents/actions/<action_id>.json`. A shell-based listener
   (`didio-action-listener.sh`) polls this directory every 5 seconds,
   processes each file, and archives it to `logs/agents/actions/archive/`.

2. **File-based flag system**: Agents raise flags by writing JSON files to
   `logs/agents/flags/`. The dashboard reads these via aggregated
   `flags.json`. The listener can resolve flags when processing actions.

3. **Polling-based listener (not inotify/fswatch)**: The listener uses a
   simple `sleep + ls` loop, which works identically on Linux, macOS, and
   Windows Git Bash.

4. **Vite dev-server middleware**: During development, a Vite plugin
   serves `flags.json`, `pipeline-state.json`, and `POST /api/actions`
   by reading/writing the same file directories. Production uses static
   file serving with the same file layout.

## Consequences

**What becomes easier:**
- Zero infrastructure beyond the filesystem
- Consistent with the existing `state.json` polling pattern
- Full auditability: every action and flag is a JSON file on disk
- Cross-platform: works on Linux, macOS, Windows Git Bash
- Offline-capable: no network dependency between dashboard and pipeline

**What becomes harder:**
- Polling latency of up to 5 seconds for action processing
- No real-time push updates (dashboard polls every 2 seconds)
- Concurrent action writes could theoretically race (mitigated by UUID
  filenames and atomic `mv` for archival)

**Trade-off accepted:** The 2-5 second latency is acceptable for a
developer tool. The simplicity and reliability of file-based communication
outweigh the latency cost. If sub-second latency becomes critical in the
future, a websocket layer can be added on top of the same file-based
storage without breaking the existing architecture.

## Alternatives considered

- **SQLite database** -- Rejected. Adds a dependency, requires schema
  migrations, and the current state.json pattern already works well.
  Over-engineering for the use case.

- **WebSocket server** -- Rejected. Requires a persistent Node.js process,
  complicates the deployment story, and is unnecessary for a polling-based
  dashboard that already updates every 2 seconds.

- **inotify/fswatch-based listener** -- Rejected. Not available on Windows
  Git Bash (MINGW64). Would require different implementations per platform.
  Polling every 5 seconds is simple and reliable.
