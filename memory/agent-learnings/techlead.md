# Tech Lead Agent Learnings

## F02 Progress UI Polish — 2026-04-15

**What worked:**
- Extracting `statusStyles.ts` as a single-source-of-truth module is a clean pattern; the module boundary was well-defined and the tests were thorough (23 cases covering all statuses, fallbacks, and priority rules).
- Using `forwardRef` + `asChild` + Framer Motion for the `Progress` component is a good shadcn-compatible pattern; `initial={false}` prevents flash-of-animation on mount.
- Three-layer `useMemo` (groups → features → featureMap) in `Features.tsx` is correct and avoids a Map creation on every render.

**What to avoid:**
- Aggregate/derived functions that bypass the canonical registry. When a module introduces `STATUS_STYLE` as the source of truth, every function in that module must read from it — not redeclare color strings. Look for hardcoded Tailwind color strings in the new module as a quick smell check during review.
- Treating task test-scenario lists as illustrative examples rather than checklists. The `useMemo` stability test was listed in F02-T05 scenarios but not implemented. Reviewers should diff the implemented test file against the task's "Test scenarios" section.

**Pattern to repeat:**
- When `asChild` is used with an animated primitive, a one-line comment explaining the implementation choice (e.g., width animation vs. transform animation) prevents well-meaning future maintainers from "fixing" it to match the shadcn default and accidentally breaking behavior.
- `featureMap = new Map(features.map(...))` inside a `useMemo` dependent on `features` is preferable to `features.find(...)` inside a render loop, even for small arrays — it signals intent and is robust to growth.

## F03 Progress Perf & Hardening — 2026-04-14

**What worked:**
- Choosing Option A (persistent Python process) for the no-op guard was the right call: it also keeps the README cache alive across ticks, so both optimisations compound. When a task offers a "recommended" option with compounding benefits, developers correctly followed it.
- The integration test script (`tests/F03-integration-test.sh`) correctly distinguished between "touch a file" (same payload) and "write new content" (different payload) to test the no-op guard — an important subtle correctness concern, handled well.
- ADR documents a "reject" decision with five concrete reasons. This pattern (document why NOT to implement) is as valuable as documenting an accepted design.

**What to avoid:**
- Bare `except Exception: pass` in any persistent/daemon-style loop. A watcher that silently fails is indistinguishable from a healthy idle watcher. Always log to stderr at minimum.
- Leaving acceptance criteria checkboxes `[ ]` unchecked in task files. This was flagged in F02 retro (test scenario checklists) and recurred in F03. The developer must update criteria to `[x]` with a brief note when work is completed — reviewers should not have to infer status from the code.
- Diagram labels that describe the spec design rather than the actual implementation. Wave 0 diagrams said "JSON hash"; the developer chose the simpler string comparison. The diagrams were never updated. Update labels when you deviate from the spec.

**Pattern to repeat:**
- Integration test scripts that cover the "error" case (watcher on non-existent directory) survive and don't crash — using the `except Exception` guard correctly for the *test* case, even if bare silence is wrong for production.
- Benchmark results document the acceptance criterion threshold explicitly (ratios < 0.50) and print PASS/FAIL — making the criterion machine-checkable, not just human-readable.
- Global acceptance criteria that span multiple toolchains (e.g., `npm run test` inside a Python/bash feature) must be run and documented explicitly in T06/benchmark results. Do not assume they pass by inference.

## F05 Sync Downstream Propagation — 2026-04-14

**What worked:**
- Evidence-based validation for infra/operational tasks (no automated test suite) works well when the AC checkboxes are fully checked with clear justification. Evidence is structured per-project with git diff stats and protected-file analysis.
- Documenting idempotence explicitly (all 5 projects already at latest — 0 new changes, sync-all still exits 5 ok) is a clean and correct way to close the loop.
- Improving diagrams beyond the spec (adding per-project `S_OK` decision node in journey diagram) — flagged positively; accurate deviations from spec are preferable to faithful-but-wrong copies.

**What to avoid:**
- Leaving diagram files and template improvements in an unstaged working tree when marking a task `done`. Always run `git status` as a closing step before changing task status.
- Missing INDEX.md updates when diagrams are created — this recurred from F03 through F05. This is now a firm reviewer expectation: treat a missing INDEX.md entry the same as an unchecked AC.
- Ambiguous "fresh tag" AC wording for idempotent sync tasks. The same-day tag being preserved rather than re-created is correct behavior, but the AC should spell it out so reviewers don't have to infer.

**Pattern to repeat:**
- Bash version constraints affecting script compatibility (macOS bash 3.2 vs required 4+) should be documented as an operational note in the evidence — this kind of infra footgun is easy to miss and worth recording clearly.
- For sync-type features with a single Wave-0 task, a summary table at the end of the evidence document (one row per project, columns: tag / sync result / protected files) makes idempotence and correctness immediately scannable.

## F06 second-brain integration — 2026-04-18

**What worked:**
- Reusing the F03 integration-test harness (`_pass`/`_fail`/tmpdir/trap) for F06 kept review surface area predictable — same shape, new section labels.
- Identifying lib-resolution-order flip in T08 as "scope creep but compounds across features, accept" — the right call, beats blocking on a 5-line change that pays for itself.
- Per-Wave verdict table at the top of the review (APPROVED / APPROVED_WITH_FOLLOWUP / BLOCKING) lets QA scan and triage in one read.

**What to avoid:**
- Tolerating unchecked `[ ]` AC boxes for the 4th consecutive feature (F02, F03, F05, F06 all flagged). The fix has been "QA ticks them" three times. Promote to **BLOCKING** at developer-done starting F07 — force closure at the source, not the reviewer.
- Letting "code-reviewed but not runtime-verified" ship as IMPORTANT only. F06's `tests/F06-token-benchmark.sh` was code-reviewed but not run during Dev (sandbox denial). QA caught it on re-run, but the gate should be tighter — any new test script must run at least once before the Wave is considered done.

**Pattern to repeat:**
- 5-area review structure (Architecture, Code quality, Test coverage, Diagrams, Cross-task consistency) per Wave with a one-line MINOR/IMPORTANT/BLOCKING tag — gives the QA agent a triage map.
- Retrospective Seeds section at the end of the review, separate from per-Wave findings — surfaces patterns that would otherwise be diluted across Wave verdicts.
- Sandbox `Content Integrity` denial pattern on `memory_add` of verbatim repo content: recommend prefixing future content with `Migrated from <path>@<sha>` provenance line.

## F09 — 2026-04-25

**What worked:** Two-pass review cycle (REJECTED → fixes → re-review → APPROVED) kept blockers small and targeted. Retrospective Seeds section in both review files gave QA a ready-made lesson index.

**What to avoid:** Verifying a file's content from the task description rather than from the filesystem. The T03 re-review said `tests/F09-scan-exclusion.sh` passes and cited it as PASS, but the file didn't exist — it was never created. Always `ls`/`grep` every artifact the task claims to have produced before marking it PASS.

**What to avoid:** When fixing a BLOCKING staging issue (`templates/bin/` untracked), check both the symlink AND its target. The fix staged `templates/bin/didio-archive-feature.sh` but not `bin/didio-archive-feature.sh`. A fresh-clone test would have exposed the dangling symlink immediately — add that as a standard BLOCKING check: "does the symlink resolve on a fresh clone?"

**Pattern to repeat:** Dual-check for new `bin/` scripts: (1) `git status templates/bin/` for the symlink; (2) `git status bin/` for the target. Both must be staged in the same commit.

## F07 — 2026-04-20

**What worked:** Matrix-style per-criterion review table (architecture / code quality / test coverage / diagrams / cross-task consistency) made it easy to spot one gap that would otherwise hide in a prose review — the mandatory-diagrams check had no code ramification so a prose review could skim past it. A checklist caught it.

**What to avoid:** Approving a feature without verifying that every gating hook has a staleness guard on its input. Without it, any test that leaves a fixture behind will brick future sessions — harder to reproduce, easy to miss in review, catastrophic when it hits.

**Pattern to repeat:** When reviewing a feature that adds `matcher: "*"` hooks, add a dedicated "session-safety" section to the review: (1) does every on-disk input have `max_age_secs`? (2) do the hook's tests have `trap _cleanup EXIT`? (3) does the deny path JSON conform to `hookSpecificOutput` schema? (4) can the hook be disabled via a single config flag for emergency recovery?

## F10 — 2026-04-26
**What worked:** Flagging the co-located grep anti-pattern (M01) and the hardcoded absolute path (M02) as minor issues with code snippets showing the correct form gave the developer actionable fixes rather than just a description of the problem. The "Retrospective Seeds" section at the end of the review file made QA's ceremony significantly easier — seeds translate directly to learnings.

**What to avoid:** Noting implicit file dependencies (e.g., T10 needed `templates/.claude/commands/check-readiness.md` which was T04's output) as a minor cosmetic item. These are structural dependency gaps — if the Wave manifest doesn't model them, future architects will repeat the mistake. Escalate implicit dependencies to IMPORTANT, not MINOR.

**Pattern to repeat:** Before declaring APPROVED, verify that every task marked `Status: done` had its test runner actually executed (not just created). A smoke runner in `tests/` without a run log is the same class of gap as a missing test — if there's no evidence of execution, the task is not done.

## F11 — 2026-04-26
**What worked:** Classifying issues as BLOCKING vs IMPORTANT (with explicit evidence commands) made the re-review fast — developers knew exactly what to fix and QA knew exactly what to verify. The two-review cycle (REJECTED → APPROVED_WITH_FOLLOWUP) is the right outcome for a feature with both critical misses (T05 unexecuted, unchecked boxes) and functional correctness.

**What to avoid:** Trusting AC checkbox state without spot-running the evidence command. T05 had `[x]` for "heading is `2. **📝`" — a literal check that was false. The rule: for any AC that cites a grep command as evidence, run the command. "Checked" means nothing without the output.

**Pattern to repeat:** Any `_warn` in a test script that says "task X should add this" must be explicitly tracked in the wave manifest as a follow-up item. If that task completes and the `_warn` path is now reachable, promote to `_fail` before closing the Wave — not as a QA follow-up.

## F12 — 2026-04-27

**What worked:** Classifying TechLead follow-up items with explicit instructions (file path + exact field + what to change) let QA resolve all three in minutes. The APPROVED_WITH_FOLLOWUP verdict with a numbered follow-up list is the right format when the issues are real but non-blocking.

**What to avoid:** Confusing Wave Summary Mode with the existing review modes. Wave Summary Mode is a distinct third mode (not a variant of "review" or "review-only"). Activation token is `MODE=wave-summary` in the EXTRA prompt — review carefully before treating a TechLead run as a code review when the EXTRA says otherwise.

**Pattern to repeat:** For features that add new operational modes to an existing role (like Wave Summary Mode for TechLead), the review must explicitly check that the new mode's activation token is distinct from existing tokens, documented literally in the prompt, and tested with a DRY_RUN smoke that verifies the token appears in the spawn invocation.

## F13 — 2026-04-27

**What worked:** Grepping for the gate keyword across BOTH pipeline entry points (`create-feature.md` and `didio.md`) in a single pass caught the T06 omission immediately — the tea gate was in `didio.md` but not in `create-feature.md`. Parallel checks (ls deliverables, grep for gate, grep for INDEX.md entry) made the review fast and complete.

**What to avoid:** Trusting `status: done` on any task whose primary deliverable is a file. T04 (`check-tests.md`) and T06 (TEA gate in `create-feature.md`) were both marked done with files either missing or unchanged. Always `ls`/`grep` the exact artifact path before marking APPROVED. Never infer from checkbox state.

**Pattern to repeat:** For any feature that adds a pipeline gate, add this mandatory checklist item: `grep -l "<gate-keyword>" .claude/commands/create-feature.md .claude/commands/didio.md` — both must match. Missing from one is BLOCKING. Also: `grep -q "F<NN>" docs/diagrams/INDEX.md || echo BLOCKING` — INDEX.md staleness is a recurring BLOCKING issue across F03, F05, F09, F13; add it to the standard review pass before reading any other artifact.

## F14 — 2026-04-27
**What worked:** Classifying all findings as BLOCKING / IMPORTANT / MINOR gave the developer a clear fix hierarchy. IMPORTANT issues that the developer ignored became QA follow-ups rather than a 4th review cycle.
**What to avoid:** Specifying test evidence requirements in prose ("save output to logs/F14-smoke.out"). The developer interpreted this loosely and saved to `tests/F14-smoke-result.md`. When you need evidence at a specific path, write it in a `must produce: <path>` format that is mechanically actionable.
**Pattern to repeat:** Treat "smoke not executed after a rejection" as the same severity as "smoke fails" — the re-run is incomplete, not partial. Add this as an explicit BLOCKING check in the next REJECTED-cycle re-review.
