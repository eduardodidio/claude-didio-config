# ADR-0006: External Tool Integrations (Opt-in CLI Extensions)

**Status:** Accepted
**Date:** 2026-09-21
**Feature:** F28

## Context

Two external CLIs complement the claude-didio-config framework:

- **Graphify** (`uv tool install graphifyy`) — generates a knowledge graph of the
  codebase via tree-sitter AST. Agents consult the graph before reading files,
  navigating with more precision and fewer tokens.
- **RTK** (`winget install rtk-ai.rtk` / `brew install rtk`) — a Rust proxy that
  compresses bash output before it reaches the LLM context (up to 90% reduction).
  Only affects Bash tool calls (Read/Grep/Glob natives don't pass through the hook).

Both tools are external binaries not bundled with the framework.

## Decision

Integrate external CLIs as **opt-in extensions** following the established
**config / hook / smoke trifecta** pattern (same as second-brain in F24):

1. **Config block** in `didio.config.json` — `enabled: false` by default.
2. **Install helper** — `bin/didio-install-<tool>.sh` with platform detection,
   prerequisite checks, and sanity verification.
3. **Smoke check** — `bin/didio-<tool>-smoke.sh` with graceful degradation:
   disabled = silent exit 0, enabled + found = exit 0, enabled + missing = WARN.
4. **CLI subcommand** — `didio <tool>` as a thin wrapper that checks enabled +
   PATH and execs the real binary.

This pattern is deliberately conservative:
- No tool modifies project files automatically.
- No tool blocks the pipeline on absence (graceful degradation).
- Install is always interactive (requires user confirmation).

## Consequences

- New tools can be added by replicating the trifecta without modifying core
  framework logic.
- Users who don't need these tools see zero impact (config defaults to disabled).
- The framework can suggest tool usage (e.g., Graphify nudge on Read) without
  requiring it.
