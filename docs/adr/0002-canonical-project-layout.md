# ADR-0002: Canonical Project Layout

**Status:** accepted
**Date:** 2026-04-14
**Deciders:** @eduardodidio

## Context

The `/install-claude-didio-framework` skill materialises a set of files into a
downstream project, and a forthcoming `didio-sync-project.sh` script must keep
those files up-to-date as the framework evolves. Without an authoritative
reference, the sync script has no way to decide:

- Which files it owns (and may overwrite)
- Which files belong to the user (and must never be touched)
- How to handle files that exist in both sides and must be *merged* rather
  than replaced (e.g. `settings.json`)

This ADR defines that authoritative reference: the canonical project layout.

## Decision

Every downstream project bootstrapped with `claude-didio-config` **must**
contain the following directory tree. Files are annotated as:

- **[framework]** — created by the framework, synced on every `didio-sync`
  run. Local edits will be overwritten.
- **[user]** — created by the framework on first install, but owned by the
  project. The sync script must never overwrite these.
- **[merge]** — framework-managed with additive-merge semantics (see §Merge
  strategies below).
- **[generated]** — created at runtime; never synced.
- **[gitignored]** — kept locally but excluded from version control.

```
<project-root>/
├── .claude/
│   ├── agents/                         # Claude Code subagent definitions
│   │   ├── architect.md                [framework]
│   │   ├── developer.md                [framework]
│   │   ├── qa.md                       [framework]
│   │   └── techlead.md                 [framework]
│   ├── commands/                       # Claude Code slash-command definitions
│   │   ├── create-feature.md           [framework]
│   │   ├── dashboard.md                [framework]
│   │   ├── didio.md                    [framework]
│   │   └── plan-feature.md             [framework]
│   ├── settings.json                   [merge]   ← additive, never shrink
│   └── settings.local.json             [user]    ← NEVER synced
│
├── agents/                             # Orchestrator, prompts, and workflows
│   ├── orchestrator.md                 [framework]
│   ├── prompts/
│   │   ├── architect.md                [framework]
│   │   ├── developer.md                [framework]
│   │   ├── qa.md                       [framework]
│   │   └── techlead.md                 [framework]
│   └── workflows/
│       └── feature-workflow.md         [framework]
│
├── docs/
│   ├── adr/
│   │   ├── 0000-template.md            [framework]
│   │   └── 0001-adopt-claude-didio-framework.md  [user]
│   ├── diagrams/
│   │   ├── README.md                   [framework]
│   │   ├── architecture.md             [user]
│   │   └── templates/
│   │       ├── architecture.mmd        [framework]
│   │       └── user-journey.mmd        [framework]
│   ├── prd/
│   │   └── template.md                 [framework]
│   └── README.md                       [framework]
│
├── logs/
│   └── agents/
│       ├── .gitkeep                    [framework]
│       ├── *.jsonl                     [generated] [gitignored]
│       └── *.meta.json                 [generated] [gitignored]
│
├── memory/
│   └── agent-learnings/
│       ├── architect.md                [user]
│       ├── developer.md                [user]
│       ├── qa.md                       [user]
│       └── techlead.md                 [user]
│
├── tasks/
│   └── features/
│       └── FXX-template/               [framework]  ← reference template
│           ├── FXX-README.md
│           └── FXX-T01.md
│
├── CLAUDE.md                           [merge]   ← section-level merge
└── didio.config.json                   [user]    ← NEVER synced
```

### Why two `agents/` directories

`.claude/agents/` is consumed directly by Claude Code: each `.md` file in that
directory registers a subagent that Claude Code can invoke by name. These files
are pure role-definition prompts with no project context.

Root `agents/` holds files consumed by the `didio` CLI, not by Claude Code
directly:

| Path | Consumed by |
|------|-------------|
| `agents/orchestrator.md` | `didio spawn-agent` when selecting a run strategy |
| `agents/prompts/*.md` | `didio spawn-agent <role>` as the system prompt |
| `agents/workflows/feature-workflow.md` | `didio run-wave` |

Both directories are required. Deleting either breaks half the pipeline.

## Merge strategies

### `.claude/settings.json`

`settings.json` holds an `allow` array of permitted Claude Code tool calls. The
sync script must:

1. Parse the existing file.
2. Parse the framework's template version.
3. Produce a union of the two `allow` arrays (no duplicates).
4. Write the merged result back.

**Invariants:**
- Entries already present in the project are never removed.
- `settings.local.json` is never read, written, or touched.
- The merge is idempotent: running it twice produces the same result.

### `CLAUDE.md`

`CLAUDE.md` is divided into named sections delimited by HTML-style comment
markers:

```markdown
<!-- didio:section:stack -->
...
<!-- /didio:section:stack -->
```

The sync script replaces framework-owned sections (defined in the template)
while leaving user-authored sections untouched. If a section marker is absent
in the project file, the sync script appends the section at the end rather than
aborting.

Framework-owned sections: `stack`, `build`, `test`, `run`, `agents`.
User-owned sections: everything else (mission, conventions, diagrams, etc.).

## Files that are NEVER synced

| File | Reason |
|------|--------|
| `didio.config.json` | Contains project-specific config (name, model overrides). Overwriting would destroy user customisation. |
| `.claude/settings.local.json` | Contains user-local permissions (API keys, personal allow-list). Never committed; never synced. |
| `memory/agent-learnings/*.md` | Accumulate project-specific retrospective learnings. Overwriting erases institutional memory. |
| `docs/adr/0001-adopt-*.md` | Filled in with project name and owner on first install; user-owned thereafter. |

## Non-standard ADR directories

Some projects use `docs/ADR/` (uppercase), `docs/architecture/decisions/`, or
`docs/architecture/` instead of `docs/adr/`. The sync script handles this as
follows:

1. Check for `docs/adr/` (canonical). If present, sync to it.
2. If absent, check `docs/ADR/` and `docs/architecture/decisions/` (common
   alternates). If found, sync to that path and log a warning recommending
   migration to `docs/adr/`.
3. If none exist, create `docs/adr/` and proceed.

The `0000-template.md` is always synced to whatever ADR directory is resolved
in step 1–3.

## Consequences

**Easier:**
- `didio-sync-project.sh` has a single source of truth for what to copy, skip,
  and merge. No heuristics required.
- New framework files can be introduced by adding them to this ADR and the
  `templates/` tree; sync scripts pick them up on next run.
- Downstream maintainers can audit exactly what the framework owns.

**Harder:**
- The canonical layout must be updated here whenever a file is added or removed
  from `templates/`. This is a process dependency, not a technical one.
- Projects that deviate from the layout (e.g., no `agents/` directory) will
  need a one-time migration before `didio-sync` can run cleanly.

## Alternatives considered

- **Sync everything, no user-owned files** — rejected. `didio.config.json` and
  `memory/agent-learnings/` are inherently project-local. Overwriting them on
  sync would destroy user data with no recovery path.
- **Manifest file per project** — rejected. A `didio.manifest.json` listing
  which files are local overrides adds tooling complexity. The canonical ADR
  is simpler and does not require per-project state.
- **Git submodule for `templates/`** — rejected. Submodules require every
  downstream maintainer to understand submodule mechanics. Copy-on-sync is
  simpler and gives the user a stable, editable copy.
