# ADR-0005: Neutral skill-compile model

**Status:** accepted
**Date:** 2026-06-13
**Deciders:** @eduardodidio

## Context

Skills (slash commands + role prompts) are today authored directly in
provider-specific formats: `.claude/commands/` (slash commands),
`.claude/agents/` (subagent definitions), and `agents/prompts/` (role
prompts), all consumed only by Claude Code. F01 adds Codex as a second
provider, which expects its own prompt/instruction layout
(`~/.codex/prompts/` for reusable prompts and `AGENTS.md` for
project-level agent instructions). Authoring and maintaining the same skill
content twice, in two formats, would drift over time and double the
maintenance cost (AC2, AC5).

## Decision

Author skills once in a **neutral source directory** (`skills/`) and compile
them to each provider's native format via a `compile-skills` step wired into
`sync-project` (task T14):

- **Source of truth:** `skills/` (checked into the repo).
- **Claude output (generated):** `.claude/commands/` (slash commands),
  `.claude/agents/` (subagent definitions), and `agents/prompts/` (role
  prompts) — derived from the same neutral source.
- **Codex output (generated):** `~/.codex/prompts/` (reusable prompts) and
  `AGENTS.md` (project-level agent instructions).
- Generated outputs are not edited by hand; re-running `compile-skills` is
  idempotent and overwrites them deterministically.
- Subagent definitions (`.claude/agents/`) have no Codex equivalent and are
  **skipped** when compiling for Codex — this is a documented gap, not an
  error.

## Consequences

- Skill content (instructions, role prompts, slash-command bodies) is edited
  in exactly one place; both providers stay in sync automatically via
  `compile-skills`.
- `sync-project` becomes the single entry point that keeps a downstream
  project's `.claude/` and Codex prompt directories up to date after a
  framework update.
- Provider-specific syntax differences (e.g. Claude subagent frontmatter vs.
  Codex prompt files) are handled by the compiler, not by skill authors.
- Because subagents are skipped for Codex, any role that depends on a
  Claude-only subagent currently has reduced fidelity when run under Codex —
  acceptable for F01 and tracked as a known gap (AC4).
- Generated directories must be excluded from manual edits; a future check
  could detect hand-edits to generated output and flag drift, but this is not
  part of F01.

## Alternatives considered

- **Author skills separately per provider** — rejected: doubles maintenance
  and guarantees drift between Claude and Codex behavior over time.
- **Generate Codex output on-the-fly at spawn time (no compile step)** —
  rejected: makes `~/.codex/prompts/` and `AGENTS.md` non-inspectable and
  couples skill authoring to runtime, complicating debugging and review.
- **Drop subagent support for Codex roles entirely (error instead of skip)**
  — rejected: would block any role with a subagent dependency from running
  under Codex at all, instead of degrading gracefully as a documented gap.
