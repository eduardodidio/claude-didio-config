# ADR 0010: Black Hawk Desktop — Tauri v2 Architecture

**Status:** Accepted
**Date:** 2026-11-26
**Feature:** F32

## Context

Black Hawk Alpha needs a persistent desktop presence — system tray, chat,
board overview, alerts, and settings. The existing dashboard (F01-F17) is
web-based and runs in a browser tab. We need a native desktop experience
that launches at startup and stays in the background.

## Decision

Use **Tauri v2** (Rust backend + React frontend) for the desktop app:

- **Tauri v2** over Electron: ~10MB binary vs ~100MB+, native OS integration
  (tray, notifications, autostart), Rust backend for file I/O and CLI bridge.
- **React 18 + shadcn/ui** reused from the dashboard for consistent UX.
- **Rust commands shell out to didio CLI** scripts rather than reimplementing
  triage/promote/defer logic — single source of truth stays in bash.
- **File watcher** (notify crate) monitors logs/flags, logs/warroom,
  tasks/features, and logs/overlord for real-time updates.
- **Chat persistence** via JSONL files in `logs/overlord/chat-YYYY-MM-DD.jsonl`.
- **Settings** stored in `~/.claude-didio-config/blackhawk/settings.json`.

## Alternatives Considered

1. **Electron**: Rejected — too heavy, no Rust advantage.
2. **CLI-only**: Rejected — operator wants visual dashboard + notifications.
3. **Browser extension**: Rejected — doesn't survive tab close, no tray.

## Consequences

- New `blackhawk-desktop/` directory with separate build pipeline.
- Rust toolchain required for development/build (not for framework users
  who consume pre-built binaries).
- React components can be shared with dashboard but are not shared yet
  (copy for now, extract to shared package in V1+).
