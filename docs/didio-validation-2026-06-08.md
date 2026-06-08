# /didio Validation + Meta-Agent Live Test — 2026-06-08

Validation pass over the `/didio` framework, with a live end-to-end test of
the new meta-agents (**Gandalf** = `t800` orchestrator, **Saruman** = `t1000`
governance reviewer) and a display-label rename. Performed against the repo
itself (`DIDIO_HOME=$(pwd)`), dogfood mode.

## TL;DR

- **All 23 `/didio` menu options are correctly wired** (scripts, skills,
  configs, prompts present). Static audit: PASS.
- **Gandalf (t800) and Saruman (t1000) work end-to-end** with high-quality
  output. Logic test: PASS.
- **One real bug found & fixed:** the two meta-agent launchers shipped
  **without the exec bit**, so the `didio t800` / `didio t1000` CLI
  entrypoints (and the t800→t1000 auto-governance chain) were broken
  (`exit 126`). Fixed via `chmod +x`.
- **Rename applied** (display-only): `T-800`→`Gandalf`, `T-1000`→`Saruman`
  across 175 occurrences in 28 files. All internal identifiers (`t800`,
  config keys, CLI subcommands, filenames, role prompts) left unchanged.

---

## Phase 1 — Static audit of the 23 menu options

Every menu action resolves to an existing script/skill/config. Summary:

| Group | Options | Status |
|-------|---------|--------|
| Work pipelines (create-feature, bug, review, retro, plan, PRD, POC) | 1,2,3,7,8,14,16,20 | ✅ wired |
| Visibility (status, dashboard, docs, list-planned) | 4,5,6,15 | ✅ wired |
| Config toggles (turbo, economy, parallel, models, highlander) | 9,10,11,12,13 | ✅ wired |
| Greenfield (brainstorm, research, product-brief) | 17,18,19 | ✅ wired |
| **Meta-agents (NEW)** — Gandalf orchestrate, Saruman governance, decision log | 21,22,23 | ✅ wired + live-tested |

Confirmed present: all `bin/didio-*.sh`, all `.claude/commands/*.md`,
`logs/agents/state.json`, config helpers
(`didio_t800_enabled`, `didio_t1000_enabled`, `didio_auto_governance`,
`didio_write_config`, `didio_read_config_path`).

### Minor findings (non-blocking)

1. **Stale header count** — `didio.md` header says *"este menu tem 19 itens"*
   but the menu now lists 23 options. Cosmetic doc drift.
2. **Two menus, divergent numbering** — the slash menu (`didio.md`) numbers
   the meta-agents 21/22/23; the terminal menu (`didio-menu.sh`) numbers them
   16/17. Independent UIs, but the inconsistency is a papercut for anyone
   cross-referencing.
3. **Root vs template command drift** — root `.claude/commands/create-feature.md`
   and `plan-feature.md` carry the Gandalf gate section; this is consistent
   with templates, but worth keeping in sync on future edits.

---

## Phase 2 — Live test of Gandalf (t800) + Saruman (t1000)

**Setup:** temporarily enabled `meta_agents.t800/t1000`, fed a real strategic
decision request (which rename strategy to use), ran `didio t800`. Config
restored to `disabled` (default) afterward. **Artifacts verified on disk** —
not exit codes (known false-positive: spawn marks `exit=2` on any non-zero
tool result).

### Result: PASS (logic), with a plumbing bug

- **Gandalf** produced `logs/decisions/D-20260608-001.json`: a well-formed
  decision with 2 options, concrete pros/cons, a justified rationale, and a
  structured `actions` array. It correctly invoked the project's
  *no-ceremony-for-ceremony* principle and chose the display-label-only path.
- **Saruman** produced `logs/governance/G-D-20260608-001.json`: verdict
  `agree` (confidence 0.8), with genuinely useful findings — it detected
  **anchoring** (binary framing missed a deprecation-alias middle path) and
  **optimism bias** (correctly predicted that "T-800"/"T-1000" strings are
  hardcoded across many template files, which the rename confirmed: 175
  occurrences). The governance report was correctly merged back into the
  decision (`status: reviewed`).
- The decision log CLI (`didio decisions --recent`, menu option 23) rendered
  the record correctly.

### BUG (found + fixed): missing exec bit on meta-agent launchers

`bin/didio-t800.sh` and `bin/didio-t1000.sh` were committed `-rw-r--r--`
(no `+x`), unlike every other `bin/didio-*.sh`. Because the `didio`
dispatcher and the auto-governance handoff use `exec`, the entrypoints
failed with **`Permission denied` (exit 126)**:

- `didio t800 …` → broken
- `didio t1000 …` → broken
- inside `didio-t800.sh`, the auto-governance call to `didio-t1000.sh` →
  broken (so Gandalf decisions never got auto-reviewed via the CLI path)

**Fix applied:** `chmod +x bin/didio-t800.sh bin/didio-t1000.sh`. Verified
both entrypoints now execute. Git will record the mode change (100644→100755)
on commit.

> **Note for downstream/install:** the same broken mode exists in any prior
> copy under `~/.claude-didio-config/bin/`. Re-running `install.sh` /
> `didio sync-project` after committing this mode change propagates the fix.
> Recommend a guard so this can't regress (see remediation R3).

---

## Phase 3 — Rename (display-label only)

Per decision: **Gandalf = t800**, **Saruman = t1000** (kept as requested).
Saruman flagged that this inverts role semantics (Saruman = the *corrupted*
wizard, assigned to the integrity/governance reviewer) — recorded here as a
note; mapping kept per maintainer's explicit choice.

- Replaced exact display tokens `T-800`→`Gandalf`, `T-1000`→`Saruman`.
- **175 occurrences across 28 files**: prompts (`t800.md`/`t1000.md` headers
  & body), `orchestrator.md`, both menus (slash + terminal), the `/orchestrate`
  & `/governance-review` skill descriptions, the `create-feature`/`plan-feature`
  gate sections, the `didio` dispatcher help, launcher help/echo strings,
  and agent-learnings headers — in both root and `templates/`.
- **Identifiers untouched** (verified): `t800`/`t1000` lowercase, config keys
  `meta_agents.t800/t1000`, CLI subcommands `didio t800`/`didio t1000`,
  filenames (`didio-t800.sh`, `agents/prompts/t800.md`), internal role string,
  and machine `DIDIO_DONE: t800 …` signals.
- Added a **name↔identifier map** note to `orchestrator.md` so a future
  `grep t800` connects back to the Gandalf display name (defuses the
  naming-mismatch debt Saruman flagged).
- Post-rename checks: 0 residual `T-800`/`T-1000`; `bash -n` clean on all 6
  scripts; `didio t800 --help` now reads *"Gandalf strategic orchestrator"*.

---

## Remediation plan (remaining items)

| ID | Item | Severity | Fix | Status |
|----|------|----------|-----|--------|
| R1 | Exec bit missing on **three** dispatched scripts: `didio-t800.sh`, `didio-t1000.sh`, **`didio-decisions.sh`** | **High** (`didio t800`/`t1000`/`decisions` + auto-governance broken, exit 126) | `chmod +x` all three | ✅ **applied** |
| R2 | Name↔identifier mapping not documented | Low | One-line note in `orchestrator.md` | ✅ **applied** |
| R3 | No guard preventing exec-bit regression | Medium | `tests/F27-dispatcher-exec-bits.sh` — derives the dispatched-script list from `bin/didio` and asserts each is executable | ✅ **applied** |
| R4 | `didio.md` header says "19 itens" (actually 23) | Low | Update the count + numbering note | ⏳ proposed |
| R5 | Slash vs terminal menu numbering divergence (21/22 vs 16/17) | Low | Align numbering or add a cross-reference note | ⏳ proposed |
| R6 | Meta-agents disabled by default — "not in use" | By design | Enable via `meta_agents.t800/t1000.enabled=true` when wanted (opt-in to avoid token cost) | ℹ️ intentional |

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
