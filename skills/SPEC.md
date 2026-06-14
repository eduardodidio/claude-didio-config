# Neutral Skill Format — SPEC

Source of truth for skills authored once and compiled to both **Claude Code**
and **OpenAI Codex CLI** by `bin/didio-compile-skills.sh` (T06/T09/T10).

This directory (`${DIDIO_HOME:-~/.claude-didio-config}/skills/`) holds one
`.md` file per skill. Compiled outputs are GENERATED — never hand-edit them.

## Front-matter

Every skill file starts with YAML front-matter:

```yaml
---
name: create-feature            # required. kebab-case, used as output filename
description: One-line summary   # required. shown in menus / help
kind: command                    # required. command | role-prompt | subagent
targets: [claude, codex]         # required. non-empty subset of [claude, codex]
role-bindings: [architect]       # optional. roles this skill binds to
---
```

### `kind` values

- `command` — a slash command (e.g. `/create-feature`).
- `role-prompt` — a role's system prompt (architect, developer, techlead, ...).
- `subagent` — a Claude Code subagent definition. No Codex analogue.

### `targets`

Subset of `[claude, codex]`. A skill with `targets: [claude]` is valid and
produces no Codex output (no `didio:codex` block required).

## Sentinels (left intact by the compiler)

Two sentinels are resolved later, at agent-spawn time, NOT by the compiler:

- `{{USE_SECOND_BRAIN}}` — substituted by `didio-spawn-agent.sh` from
  `second_brain.enabled`.
- `{{DIDIO_CHECKPOINT}}` — replaced with the checkpoint block from
  `agents/prompts/_checkpoint-block.md`.

The compiler MUST copy these sentinels verbatim into every compiled output,
regardless of target.

## Provider-override blocks

For the few places Claude and Codex differ (invocation syntax, sentinel
handling, path references like `CLAUDE.md` vs `AGENTS.md`, or
`.claude/commands` vs `~/.codex/prompts`), wrap target-specific lines in HTML
comment markers (inert in any markdown renderer):

```markdown
<!-- didio:claude -->
...Claude-specific lines...
<!-- /didio:claude -->

<!-- didio:codex -->
...Codex-specific lines...
<!-- /didio:codex -->
```

Rules:

- Lines outside any override block are **shared** and appear in every
  compiled output.
- When compiling for target X, blocks for other targets are stripped
  entirely (including their markers); the block for X is inlined with its
  markers removed.
- Override blocks must be balanced: every `<!-- didio:X -->` must have a
  matching `<!-- /didio:X -->` later in the file. An unbalanced block is a
  validation error.
- A skill may omit override blocks for a target it doesn't list in
  `targets`.

## Output-path mapping

| `kind`        | Claude output                    | Codex output                                   |
|---------------|-----------------------------------|------------------------------------------------|
| `command`     | `.claude/commands/<name>.md`      | `~/.codex/prompts/<name>.md`                    |
| `role-prompt` | `agents/prompts/<name>.md`        | `~/.codex/prompts/<name>.md` + aggregated into `AGENTS.md` |
| `subagent`    | `.claude/agents/<name>.md`        | skipped (no Codex analogue; documented note)    |

## Worked example

See `_example.md` in this directory for a minimal `kind: command`,
`targets: [claude, codex]` skill with one override block, used by the
`F01-skill-spec.sh` smoke test (and later by T09/T10).
