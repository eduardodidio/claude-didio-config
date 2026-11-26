# /didio Validation + Meta-Agent Live Test — 2026-06-08

> **Historical note (F29A):** This document was written when the meta-agents
> used the persona names Gandalf (t800) and Saruman (t1000). Those have since
> been renamed to **Handler** and **GateKeeper** respectively. References below
> preserve the original naming for historical accuracy of this validation report.

Validation pass over the `/didio` framework, with a live end-to-end test of
the meta-agents (**Handler** / **GateKeeper**) and a display-label rename.
Performed against the repo itself (`DIDIO_HOME=$(pwd)`), dogfood mode.

## TL;DR

- **All 23 `/didio` menu options are correctly wired** (scripts, skills,
  configs, prompts present). Static audit: PASS.
- **Handler and GateKeeper work end-to-end** with high-quality
  output. Logic test: PASS.
- **One real bug found & fixed:** the two meta-agent launchers shipped
  **without the exec bit**, so the `didio handler` / `didio gatekeeper` CLI
  entrypoints (and the handler→gatekeeper auto-governance chain) were broken
  (`exit 126`). Fixed via `chmod +x`.
- **Rename applied** (display-only): meta-agent display labels updated
  across 175 occurrences in 28 files. All internal identifiers
  left unchanged at the time (later updated by F29A).

---

## Phase 1 — Static audit of the 23 menu options

Every menu action resolves to an existing script/skill/config. Summary:

| Group | Options | Status |
|-------|---------|--------|
| Work pipelines (create-feature, bug, review, retro, plan, PRD, POC) | 1,2,3,7,8,14,16,20 | ✅ wired |
| Visibility (status, dashboard, docs, list-planned) | 4,5,6,15 | ✅ wired |
| Config toggles (turbo, economy, parallel, models, highlander) | 9,10,11,12,13 | ✅ wired |
| Greenfield (brainstorm, research, product-brief) | 17,18,19 | ✅ wired |
| **Meta-agents (NEW)** — Handler orchestrate, GateKeeper governance, decision log | 21,22,23 | ✅ wired + live-tested |

Confirmed present: all `bin/didio-*.sh`, all `.claude/commands/*.md`,
`logs/agents/state.json`, config helpers
(`didio_handler_enabled`, `didio_gatekeeper_enabled`, `didio_auto_governance`,
`didio_write_config`, `didio_read_config_path`).

### Minor findings (non-blocking)

1. **Stale header count** — `didio.md` header says *"este menu tem 19 itens"*
   but the menu now lists 23 options. Cosmetic doc drift.
2. **Two menus, divergent numbering** — the slash menu (`didio.md`) numbers
   the meta-agents 21/22/23; the terminal menu (`didio-menu.sh`) numbers them
   16/17. Independent UIs, but the inconsistency is a papercut for anyone
   cross-referencing.
3. **Root vs template command drift** — root `.claude/commands/create-feature.md`
   and `plan-feature.md` carry the Handler gate section; this is consistent
   with templates, but worth keeping in sync on future edits.

---

## Phase 2 — Live test of Handler + GateKeeper

**Setup:** temporarily enabled `meta_agents.handler/gatekeeper`, fed a real
strategic decision request (which rename strategy to use), ran `didio handler`.
Config restored to `disabled` (default) afterward. **Artifacts verified on
disk** — not exit codes (known false-positive: spawn marks `exit=2` on any
non-zero tool result).

### Result: PASS (logic), with a plumbing bug

- **Handler** produced `logs/decisions/D-20260608-001.json`: a well-formed
  decision with 2 options, concrete pros/cons, a justified rationale, and a
  structured `actions` array. It correctly invoked the project's
  *no-ceremony-for-ceremony* principle and chose the display-label-only path.
- **GateKeeper** produced `logs/governance/G-D-20260608-001.json`: verdict
  `agree` (confidence 0.8), with genuinely useful findings — it detected
  **anchoring** (binary framing missed a deprecation-alias middle path) and
  **optimism bias** (correctly predicted that display-name strings were
  hardcoded across many template files, which the rename confirmed: 175
  occurrences). The governance report was correctly merged back into the
  decision (`status: reviewed`).
- The decision log CLI (`didio decisions --recent`, menu option 23) rendered
  the record correctly.

### BUG (found + fixed): missing exec bit on meta-agent launchers

`bin/didio-handler.sh` and `bin/didio-gatekeeper.sh` were committed
`-rw-r--r--` (no `+x`), unlike every other `bin/didio-*.sh`. Because the
`didio` dispatcher and the auto-governance handoff use `exec`, the
entrypoints failed with **`Permission denied` (exit 126)**:

- `didio handler …` → broken
- `didio gatekeeper …` → broken
- inside `didio-handler.sh`, the auto-governance call to
  `didio-gatekeeper.sh` → broken (so Handler decisions never got
  auto-reviewed via the CLI path)

**Fix applied:** `chmod +x bin/didio-handler.sh bin/didio-gatekeeper.sh`.
Verified both entrypoints now execute. Git will record the mode change
(100644→100755) on commit.

> **Note for downstream/install:** the same broken mode exists in any prior
> copy under `~/.claude-didio-config/bin/`. Re-running `install.sh` /
> `didio sync-project` after committing this mode change propagates the fix.
> Recommend a guard so this can't regress (see remediation R3).

---

## Phase 3 — Rename (display-label only)

Per F29A decision: meta-agent display labels were updated to
**Handler** (strategic orchestrator) and **GateKeeper** (governance reviewer).

- **175 occurrences across 28 files** updated: prompts, `orchestrator.md`,
  both menus (slash + terminal), skill descriptions, gate sections, dispatcher
  help, launcher help/echo strings, and agent-learnings headers — in both root
  and `templates/`.
- Config keys, CLI subcommands, and filenames were also updated to use
  `handler`/`gatekeeper` identifiers (completed in F29A).
- Post-rename checks: `bash -n` clean on all scripts;
  `didio handler --help` reads *"Handler strategic orchestrator"*.

---

## Remediation plan (remaining items)

| ID | Item | Severity | Fix | Status |
|----|------|----------|-----|--------|
| R1 | Exec bit missing on **three** dispatched scripts: `didio-handler.sh`, `didio-gatekeeper.sh`, **`didio-decisions.sh`** | **High** (`didio handler`/`gatekeeper`/`decisions` + auto-governance broken, exit 126) | `chmod +x` all three | ✅ **applied** |
| R2 | Name↔identifier mapping not documented | Low | One-line note in `orchestrator.md` | ✅ **applied** |
| R3 | No guard preventing exec-bit regression | Medium | `tests/F27-dispatcher-exec-bits.sh` — derives the dispatched-script list from `bin/didio` and asserts each is executable | ✅ **applied** |
| R4 | `didio.md` header says "19 itens" (actually 23) | Low | Update the count + numbering note | ⏳ proposed |
| R5 | Slash vs terminal menu numbering divergence (21/22 vs 16/17) | Low | Align numbering or add a cross-reference note | ⏳ proposed |
| R6 | Meta-agents disabled by default — "not in use" | By design | Enable via `meta_agents.handler/gatekeeper.enabled=true` when wanted (opt-in to avoid token cost) | ℹ️ intentional |

> **R1 update:** while building the R3 guard, a **third** broken script
> surfaced — `didio-decisions.sh` (menu option 23, `didio decisions`) had the
> same missing exec bit. The live test had passed only because it was invoked
> via `bash`. Now fixed and covered by R3.

The R3 guard (`tests/F27-dispatcher-exec-bits.sh`) passes 15/15 and was
negative-tested (stripping a script's exec bit makes it fail with a clear
message), so the High-severity bug class can no longer regress silently when a
new `bin/didio-*` subcommand is added.

---

## Test artifacts

Created during the live test (safe to delete — test-only):

- `logs/decisions/D-20260608-001.json`
- `logs/governance/G-D-20260608-001.json`
- `logs/decisions/_requests/SMOKE-test-request.md`
