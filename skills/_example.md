---
name: example-skill
description: Minimal example skill proving the neutral skill format
kind: command
targets: [claude, codex]
---
# Example Skill

This is a shared line, present in every compiled output.

It carries sentinels verbatim: {{USE_SECOND_BRAIN}} and {{DIDIO_CHECKPOINT}}.

<!-- didio:claude -->
Invoke this as `/example-skill` in Claude Code. Project instructions live in
`CLAUDE.md`.
<!-- /didio:claude -->

<!-- didio:codex -->
Invoke this as `example-skill` via `codex exec`. Project instructions live in
`AGENTS.md`.
<!-- /didio:codex -->

Another shared line at the end.
