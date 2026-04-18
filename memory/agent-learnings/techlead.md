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
