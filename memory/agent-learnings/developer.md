# Developer Agent Learnings

## F02 — 2026-04-15

**What worked:** Wave dependency order (Wave 0 deps → Wave 1 parallel modules → Wave 2 integration) prevented file conflicts. `featureMap` (Map pre-computed in `useMemo`) is better than inline `features.find()` inside render loops.

**What to avoid:** When a module is introduced as a canonical style registry (e.g., `STATUS_STYLE`), all functions in that module must read from it — not re-declare the same literal strings. Grep for hardcoded Tailwind color strings in new registry modules before submitting. Also: task files list test scenarios as a checklist, not as illustrative examples — implement every scenario.

**Pattern to repeat:** Pre-compute a `Map<key, value>` in `useMemo` to replace O(n) `array.find()` calls inside JSX maps. When using `asChild` with Framer Motion inside a Radix primitive, animate `width` instead of `transform` to avoid conflicts with Radix's internal transform injection — add a brief comment explaining why.

## F05 — 2026-04-14

**What worked:** Evidence-based validation for infra/operational tasks with no automated suite. Per-project summary table (tag / sync result / protected files) made idempotence and correctness scannable. Improving a diagram beyond the spec (adding `S_OK` per-project decision node) is better than a faithful-but-wrong copy.

**What to avoid:** Leaving diagram files and template improvements in an unstaged working tree when marking a task `done` — run `git status` as a mandatory closing step. Failing to update `docs/diagrams/INDEX.md` when creating diagrams — this recurred in F03, F04, and F05 and now warrants a permanent checklist entry on any task that creates diagrams. Writing ambiguous "fresh tag" AC for idempotent sync tasks — the same-day tag preserved from a prior run IS correct behavior; the AC must spell out the idempotent case.

**Pattern to repeat:** Document bash version constraints as an operational note in the evidence (macOS ships bash 3.2, scripts require 4+). Always explicitly exercise and document the already-synced scenario for idempotent sync features — confirms correct no-op behavior even when no files change.

## F03 — 2026-04-14

**What worked:** Choosing Option A (persistent Python process) for the no-op guard compounds with the README cache — both optimisations survive across ticks in the same process. Module-level cache dict + `_clear_cache()` helper is the right Python pattern for process-lifetime caching that is also test-friendly.

**What to avoid:** Bare `except Exception: pass` in any persistent/daemon-style loop — a watcher that silently fails is indistinguishable from a healthy idle watcher; always log to stderr. Leaving `[ ]` checkboxes unchecked in task files (recurred from F02). Diagram labels that describe the spec design rather than the actual implementation — when you choose a simpler approach (string compare instead of MD5 hash), update the diagrams.

**Pattern to repeat:** Persistent-process refactor (bash thin-launcher `exec python3 …`): separates stateless bash setup from stateful Python loop cleanly, and eliminates the need for external `.prev_hash` temp files. ADR "reject" documents with explicit, enumerated reasoning are as valuable as "accept" ADRs. Always include cross-stack acceptance criteria (`npm run test`) explicitly in the integration test script or benchmark results — do not assume they pass by inference.

## F06 — 2026-04-18

**What worked:** Single sentinel `{{USE_SECOND_BRAIN}}` substituted via bash `${VAR//pattern/replacement}` parameter expansion in `didio-spawn-agent.sh` — no python3 spawn per prompt, fully portable, one source of truth for the on/off branch. Conservative-default config helpers (`enabled` defaults `false`, `fallback_to_local` defaults `true`) make the feature opt-in even when the JSON block is absent.

**What to avoid:** `(( PASS++ ))` in bash test harnesses — the post-increment expression evaluates to `0` on the 0→1 transition, which trips `set -e` and falsely registers a failed test inside subshells. Always use `PASS=$((PASS+1))`. Also: writing a new shell script and executing it in the same session can trip sandbox "unverified-script" denials on first run — for one-off measurements, prefer inline `python3 <<'PY'` in a Bash call; ship the dedicated `.sh` for repeat runs.

**Pattern to repeat:** When a feature evolves `bin/didio-config-lib.sh`, also flip `didio-spawn-agent.sh` to source project-local lib first (`PROJECT_ROOT/bin/didio-config-lib.sh`) before falling back to `${DIDIO_HOME}`. Compounds across all future features that touch the lib — they ship without waiting for global install to update.

## F09 — 2026-04-25

**What worked:** Copy-retro-then-move-feature order in the archive script (`copy_retro` before `move_to_archive`) means a partial failure leaves the retrospective safe in `memory/retrospectives/` even if the move fails. Single-responsibility helpers (`feature_dir`, `has_passed_qa`, `last_commit_age_days`, `copy_retro`, `move_to_archive`) made the script easy to review and test independently.

**What to avoid:** Staging only the symlink in `templates/bin/` without staging the actual script in `bin/`. On a fresh clone the symlink would be dangling, silently causing `bin/didio-sync-project.sh` to warn-and-skip instead of copying the script downstream. Pattern: when adding a new `bin/<script>`, always run `git status bin/ templates/bin/` together before marking the Wave done — both paths must be staged.

**What to avoid:** Leaving a machine-readable decision heading (used by test scripts via awk) out of sync with the actual decision taken. The `## Decision` line in `docs/F09-scan-exclusion-check.md` said `settings.json: permissions.deny` (the available mechanism) but the wave resolved to `gitignore-only`. Any doc used as machine-readable config must be updated when the decision changes scope.

**Pattern to repeat:** Bake the Branch A/B decision into the test file at read time (awk from the decision doc) rather than hardcoding the branch in the test. Makes the test self-documenting and future-proof — updating the doc is enough if the mechanism ever changes.

## F07 — 2026-04-20

**What worked:** Every JSON writer uses Python's `os.replace(tmp, target)` for atomic writes. Eliminated corruption risk across concurrent probes without needing `flock` (macOS default lacks it). Paired with mtime-based throttle (5s for probe, 60s for checkpoint-write), this was enough — no lock needed. Also: running the ccusage JSON through a defensive field-lookup (`totalTokens` / `total_tokens` / sum of `input+output+cache_*`) avoids breaking when ccusage bumps minor versions.

**What to avoid:** `npx -y <pkg>` in a hook path without a timeout. First-install on a fresh machine can take 30+ seconds; post-tool hook is backgrounded so non-fatal, but any foreground invocation would block. If needed in foreground: `perl -e 'alarm 10; exec @ARGV' -- npx -y pkg`. Also: `touch -t "$(date -u -v -N{unit} …)"` — `touch -t` reads local time, `date -u` prints UTC → backdated mtimes land in the future. Use Python `os.utime(p, (t-600, t-600))` for portable staleness fixtures.

**Pattern to repeat:** Checkpoint-style JSON files where a human/agent writes semantic fields AND a script periodically rewrites mechanical fields — always read the previous file first, preserve the semantic keys, only overwrite the mechanical ones. `didio-checkpoint-write.sh:63-72` is the reference. Prevents stomping agent-authored progress on every tool call.

## F10 — 2026-04-26
**What worked:** Fixture-based testing with `F99-` prefix completely isolated from real features. Sequential Wave 3 chain (T08→T09→T10) enforced by manifest; respecting it prevented a scenario where T10 would assert fixtures that T08 hadn't created yet.

**What to avoid:** Sync log assertions using two independent `grep -qF` calls (`grep -qF "[TOKEN]" && grep -qF "$path"`) — these check each token exists somewhere in the file, not that they co-occur on the same line. Use `grep -F "$path" "$LOG" | grep -qF "[TOKEN]"` to assert co-occurrence. Also: hardcoding absolute paths (`DIDIO_HOME="${DIDIO_HOME:-/Users/...}"`) in portable test scripts — derive from `${BASH_SOURCE[0]}` and keep the env override for CI. And: never mark a task `done` when its test runner exists but has never been executed; the AC must include a passing run, not just a created script.

**Pattern to repeat:** FORCE/debug env vars needed by sanity tasks should be designed into the agent prompt during the Wave 1 task, not added retroactively. If Wave 3 includes "run against non-planned feature", the Wave 1 prompt must already support `DIDIO_X_FORCE=1`.

## F11 — 2026-04-26
**What worked:** Single-source-of-truth architecture (question template as sole owner of prompt text) kept the command body clean and testable. Sync propagation as a one-line `copy_if_missing` addition is the right pattern for new template files.

**What to avoid:** (1) Leaving a Wave N task at `Status: planned` while Wave N+1 starts — the smoke test compensated with a `_warn` that created technical debt outliving its context. Never soft-gate to compensate for an incomplete prior-Wave task. (2) False-positive AC checkboxes: T05 marked `[x]` for "heading is `2. **📝`" when the actual heading was `16. **📝`. This class of integrity failure is harder to catch than an empty box because the checkbox appears complete. Include the actual grep output as inline evidence, not just `[x]`. (3) `_warn` in test scripts without a closing commitment — it becomes a silent regression gate.

**Pattern to repeat:** For slash-command features, structural smoke tests (grep-based, no runtime invocation) give high assertion coverage quickly. Separate the command body from the data file (template) so both can be tested independently.

## F12 — 2026-04-27

**What worked:** Running all three smokes before marking tasks done — the pattern F06/F11 broke but F12 corrected. Smoke script created = smoke must be run; the AC checkbox for "rodar X imprime N passed, 0 failed" must be checked by actually running X.

**What to avoid:** (1) Leaving skeleton status fields as-is after populating a doc. When you populate a skeleton doc created by a prior task, update `**Status:**` from "skeleton" to "populated (by FXX-TYY, YYYY-MM-DD)". One-line edit, signals completeness to future readers and QA. (2) Stale "# to be added in TXX" comments. If the approach changed (e.g., chose inline Python3 over a separate script), replace the skeleton comment with the actual approach. Never leave `# to be added in TXX` when TXX is already done. (3) Missing `## Notes from Developer` when the task spec explicitly says to create one. Body prose does not substitute — the Notes section is where reviewers and QA look first for decision evidence.

**Pattern to repeat:** For tasks that introduce a new config sub-field with a non-obvious default behavior (e.g., `wave_summary` recognized-but-not-stored), document the rationale in `## Notes from Developer` immediately — not as a TechLead follow-up item.

## F13 — 2026-04-27

**What worked:** Fixture domain diversity (audio-game / a11y-ui / trivial-text) gave distinct behavioral coverage without inflating the suite. Using `DIDIO_DRY_RUN=1` mode in `F13-tea-e2e.sh` let QA validate spawn configuration without a live Claude API call.

**What to avoid:** Marking a task `status: done` when its primary file artifact does not exist. T04 (`check-tests.md`) and T06 (TEA gate in `create-feature.md`) both fell into this pattern — "done but artifact absent" (3rd recurrence: F09-T03, F11-T05, F13-T04/T06). Before changing status: `test -f <primary-artifact-path> || echo FAIL`. Also: when a pipeline gate is added to one entry point (`didio.md`), add it to the other (`create-feature.md`) in the same task — never split across separate tasks that can execute in parallel.

**Pattern to repeat:** For any task that creates/modifies a slash command, the closing step must include `diff -q .claude/commands/<cmd>.md templates/.claude/commands/<cmd>.md` to confirm byte-identity between root and template. A one-liner that catches the most common F13-class omission.

## F14 — 2026-04-27
**What worked:** Wave 0 front-loading (permissions + config block) prevented approval gaps in Waves 1+. Three independent slash commands with no spawn kept QA validation fully structural.
**What to avoid:** Partial fix cycles — IMPORTANT issues (output path mismatch, two-level menu gaps) survived two REJECTED cycles because only BLOCKING items were fixed on each re-run. After any REJECTED verdict, fix ALL BLOCKING + IMPORTANT in the same pass. Also: never deliver infra (permissions, config) while primary deliverables (command files) are absent.
**Pattern to repeat:** Run the smoke test and verify it passes BEFORE declaring a re-run ready after a REJECTED verdict. An unexecuted test script is not evidence.

## F15 — 2026-04-27
**What worked:** Systematic spike (T01) with a machine-readable decision token before Wave 1 implementation prevented building on a false premise. `bin/didio-jsonl-errors.py` extracted as standalone parser is a clean, reusable pattern.

**What to avoid:** (1) Smoke tests routing through the CLI dispatcher (`./bin/didio spawn-agent`) rather than the implementation script directly (`./bin/didio-spawn-agent.sh`). The dispatcher may resolve to a globally installed binary that lacks the local changes — two review cycles were wasted because of this. Always call the implementation script directly and add: `# Call implementation directly — dispatcher may delegate to stale global install`. (2) False-positive AC checkboxes: checking `[x]` for "smoke exits 0" before running the smoke. A checkbox for a shell-command AC must include the actual command output as inline evidence; absence of output is a red flag.

**Pattern to repeat:** For any smoke test that exercises `didio-spawn-agent`, call `./bin/didio-spawn-agent.sh` directly (not `./bin/didio spawn-agent`). Include a header comment explaining why. This is the same dispatcher-bypass discipline as the symlink-check pattern from F09.
