# ADR-0007: RTK Hook Coexistence

**Status:** Accepted
**Date:** 2026-09-21
**Feature:** F28

## Context

RTK (rtk-ai) installs its compression hook at the **user level**
(`~/.claude/settings.json`) via `rtk init -g`. The didio framework installs its
hooks at the **project level** (`.claude/settings.json`). Both hook systems
coexist in Claude Code because project-level and user-level settings are merged
at runtime.

## Decision

1. The framework **never auto-runs** `rtk init -g` — it modifies
   `~/.claude/settings.json`, which is user-owned and may contain other
   customizations.
2. The install helper (`didio-install-rtk.sh`) installs the RTK binary only and
   prints post-install instructions telling the user to run `rtk init -g`
   manually.
3. The RTK smoke check (`didio-rtk-smoke.sh`) verifies the binary is on PATH.
   It does NOT check for the hook in `~/.claude/settings.json` — that's the
   user's responsibility.
4. Didio's project-level hooks (session guard, Graphify nudge) operate on
   `PreToolUse` and `PostToolUse` events. RTK's user-level hook wraps `Bash`
   tool calls. These are orthogonal and don't conflict.

## Consequences

- RTK and didio hooks coexist without ordering issues.
- The user retains full control over `~/.claude/settings.json`.
- If RTK changes its hook mechanism in the future, only the smoke check and
  documentation need updating — no framework code depends on RTK's hook format.
