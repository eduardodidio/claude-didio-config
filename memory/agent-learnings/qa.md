# QA Agent Learnings

## F02 — 2026-04-15

**What worked:** Tech Lead review flagged a missing test scenario and a canonical registry violation before QA ran — reading the review file first saved redundant discovery work.

**What to avoid:** Do not skip diffing the implemented test file against the task's "Test scenarios" section. Each listed scenario is a required test; if it's missing, create it — do not just report it. Also check canonical registry modules (e.g., `statusStyles.ts`) for functions that hardcode literal strings that should delegate to the registry map.

**Pattern to repeat:** Spy-based memo stability test: `vi.mock('@/lib/selectors', async (importOriginal) => { const actual = await importOriginal(); spy.mockImplementation(actual.fn); return { ...actual, fn: spy }; })` — then assert `spy.mock.calls.length` is stable after `rerender()` with same data reference. Clean, low-overhead useMemo correctness proof with no React Profiler boilerplate.

## F05 — 2026-04-14

**What worked:** For infra/operational features with no automated test suite, all 4 acceptance criteria were met by reviewing the evidence documentation in the README. Diagram accuracy was cross-checked against the actual sync scripts. Tech Lead follow-up items were triaged: INDEX.md gap (missing F04 entries) was fixed directly by QA; `didio.config.json` cosmetic change was verified as intentional.

**What to avoid:** Assuming INDEX.md is up to date when a feature creates diagrams. Carry-over gaps from prior features (F04 entries were never added) are in scope for QA to fix — a missing index entry is the same class of issue as an unchecked acceptance criterion.

**Pattern to repeat:** When the Tech Lead returns APPROVED_WITH_FOLLOWUP, triage each follow-up item: fix correctness and documentation-completeness issues (INDEX.md, diagram accuracy) directly during QA; defer commit/staging operations to the next commit wave; verify "intentional change" claims by reading the actual diff. Always check `docs/diagrams/INDEX.md` has entries for every `.mmd` file referenced in the feature task.

## F03 — 2026-04-14

**What worked:** Reading the Tech Lead review before running tests surfaced actionable follow-up items (stderr logging, diagram label fixes) that QA could fix directly rather than just report. This is the right division of labour: QA fixes what is clearly wrong; reports what is genuinely debatable.

**What to avoid:** Trusting that cross-stack acceptance criteria (e.g., `npm run test` inside a Python/bash feature) were run by the developer. Explicitly run and record every global criterion — especially ones that require tools outside the feature's primary stack.

**Pattern to repeat:** When a Tech Lead review returns APPROVED_WITH_FOLLOWUP, triage the follow-up items: fix code/diagram correctness issues directly during QA pass, record documentation-hygiene items in the QA report but don't block the verdict on them. Always re-run the full test suite after applying QA fixes to confirm nothing regressed. Check diagram labels against the actual implementation (not just the spec) — subtle vocabulary mismatches ("hash" vs "string compare") erode trust in documentation over time.

## F06 — 2026-04-18

**What worked:** Bulk-ticking AC boxes via inline `python3` with an audit-trail note (`_(QA: ticked after <evidence>)_`) under each `## Acceptance criteria` header — gives reviewers a months-from-now answer to "why is this checked". Re-running both `F06-integration-test.sh` (19/19) and `F06-token-benchmark.sh` (82%) before writing the QA report grounded the verdict in fresh evidence rather than developer self-reporting.

**What to avoid:** Marking partial outcomes with full `[x]` for the sake of a green-looking task file. T03 had 7/9 migration entries succeed; honest status is `[~] partial 7/9` plus a `[ ]` on the un-verified idempotent re-run. Honesty > optimism — the TechLead review is the source of truth, the task file just mirrors it.

**Pattern to repeat:** Dual-write retrospective (passo 3 local-append + passo 3b `memory_add` mirror) closes the loop on any feature that introduces a new memory-store path — the feature validates itself by being the first user of its own pattern. Always include a provenance-prefix line (`Mirrored from memory/agent-learnings/<role>.md@<feature>`) on `memory_add` content to lower sandbox `Content Integrity` denial risk.

## F09 — 2026-04-25

**What worked:** Cross-checking the machine-readable decision line (`## Decision` in scan-exclusion doc) against the actual implementation caught a doc/code mismatch that would have caused the scan exclusion test to select the wrong branch and fail.  Running `git status` on `bin/` and `templates/bin/` together found a dangling-symlink risk that the TechLead missed.

**What to avoid:** Trusting that TechLead APPROVED means all declared artifacts exist. F09 T03 was APPROVED but `tests/F09-scan-exclusion.sh` was never created. Pattern: for every task the TechLead reviewed, `ls`/`grep` each declared output file before accepting the verdict. TechLead reviews describe intent; QA verifies existence.

**Pattern to repeat:** For features that add new `bin/` scripts with `templates/bin/` symlinks — check both `git status bin/<script>` AND `git status templates/bin/<script>`. A staged symlink pointing to an untracked target is a dangling symlink on any fresh clone. This is a class of BLOCKING issue that doesn't show up in a code review unless you explicitly check `git status` for the target file.

## F07 — 2026-04-20

**What worked:** Stubbing `didio-spawn-agent.sh` via `DIDIO_SPAWN_CMD` env override let the e2e test drive the full pause → schedule → resume cycle without spending a single real token. 13 scenarios in < 15s including SIGTERM of real sleep-loop PIDs. Fake meta files + seeded state.json exercise the real pause.sh code path, not a mock.

**What to avoid:** Tests that seed "poisoned" fixtures (e.g. `session-budget.json` with `pct=0.99`) WITHOUT an `EXIT` trap from line 1. We bricked the host session twice during development because the smoke test's fixtures survived to the next tool call. `trap _cleanup EXIT` with a full fixture enumeration + state.json backup/restore is non-negotiable for tests that write to paths consumed by live hooks.

**Pattern to repeat:** `LC_ALL=C grep -aq` for asserting against outputs containing embedded NUL bytes (e.g. anything built from `printf '%s\0' "$@"`). Default grep in UTF-8 locale silently fails to match multi-byte patterns across nul-terminated lines. `-a` forces text mode, `LC_ALL=C` treats bytes as bytes.

**Pattern to repeat:** Portable backdating — `python3 -c "import os; os.utime('$f', ($t-600,$t-600))"` works on every platform. Never use `touch -t` for staleness tests — the format mixes local and UTC in confusing ways.

## F10 — 2026-04-26
**What worked:** Reading the TechLead review first (APPROVED_WITH_FOLLOWUP with explicit IMPORTANT/MINOR classification) made QA triage fast — IMPORTANT items get fixed, MINOR items get fixed, IMPORTANT gaps (like AC7 no test) got a new test created immediately. The QA prior-learning "create the test, don't just report it" was correctly applied: the AC7 bypass test was written and passed 9/9.

**What to avoid:** Accepting "verified via documentation text" as evidence for AC7-class features. Any env-var bypass or safety gate must have an automated structural test that asserts the token exists in every expected file — even if the behavior is a Claude slash command and can't be exercised by shell. Documentation can drift; a test catches the drift.

**Pattern to repeat:** When an AC's artifact is supposed to land at a specific path (e.g., `tasks/features/F09-*/readiness-report.md`) always `ls`/`find` that path before accepting the TechLead verdict. TechLead reviews describe intent; QA verifies existence. If the file is at a different location (e.g., in `tests/F10-fixtures/`), copy it to the declared path — the spec is authoritative.

## F11 — 2026-04-26
**What worked:** Reading both TechLead reviews (REJECTED → APPROVED_WITH_FOLLOWUP) up front reduced discovery work — the two IMPORTANT issues were clearly documented with exact file/line references. Fixing issues in-place (harden `_warn`, move option block, correct false-positive AC boxes) rather than just reporting them kept the feature moving.

**What to avoid:** False-positive AC checkboxes are a new class of integrity failure harder to catch than empty boxes. The checkbox looks complete but the condition is false. Pattern to detect: for any AC that cites a grep command as evidence, run the command and compare the output to what the checkbox claims.

**Pattern to repeat:** When a `_warn` in a test script is confirmed stale (the referenced task is done), harden it to `_fail` immediately during QA — don't defer. The swap from 1 soft-warn to 2 hard-fail assertions added 1 net assertion (31 vs 30) and made the suite a true regression gate. This is the correct end-state for any `_warn` whose trigger condition has been resolved.

## F12 — 2026-04-27

**What worked:** All three smokes (9/15/9 = 33 checks) re-run before writing the QA report grounded the verdict in fresh evidence. Triaging the three TechLead follow-up items and fixing them directly (status field, stale comment, missing Notes section) rather than just documenting them kept the feature clean without blocking the verdict.

**What to avoid:** Marking end-to-end behavioral validation as complete when only structural/DRY_RUN evidence exists. For Tier 2 features (wave summaries, sharding), structural-only is sufficient per the task spec — but the QA report must explicitly say "structural-only, end-to-end deferred" rather than silently omitting the qualification.

**Pattern to repeat:** For every AC that has a kill-switch (enabled=false, threshold=9999), the smoke must test both the ON path and the OFF path. A smoke that only tests the happy path is not a kill-switch test — it is a regression test for the feature being on. The OFF path is the one that prevents future accidental activation in downstream projects.

## F13 — 2026-04-27

**What worked:** Using `DIDIO_DRY_RUN=1` on `F13-tea-e2e.sh` validated spawn configuration (model/fallback/effort flags) and gate logic (scenarios C/C2) without a live Claude API call — covering 2 of 4 scenarios structurally. F13-sync-smoke.sh ran to exit 0, confirming AC7 per-project preservation. Reading both TechLead reviews before starting QA gave a complete picture of what was fixed vs what remained scaffold-only.

**What to avoid:** Treating e2e scenarios that require live API as "PASS" based on dry-run alone. The correct QA disposition: mark them `scaffold-only` explicitly in the report, note the scenario labels and what they would verify, and do not inflate the verdict. The distinction matters when a future QA re-runs the feature.

**Pattern to repeat:** For features with live-API-dependent e2e tests, always run the non-live scenarios (gate logic, config reads, bypass flag) first — they give structural confidence and complete AC coverage for the opt-out paths. Document live scenarios as scaffold with a one-line description of what they verify when run with real API.

## F15 — 2026-04-27
**What worked:** Reading all TechLead reviews (third review resolved prior REJECTED) up front gave a complete picture of what changed per cycle. Running all unit tests fresh (F15-exit-override: 14/14, F15-pre-tool-unit: 17/17, F09-archive: 39/39, F15-sync-regression: PASS) grounded the verdict in current evidence. The ADR Approach C inconsistency (described as "rejected" but implemented in T08) was caught by cross-referencing the decision/ADR against task notes — this class of doc/code mismatch is easy to miss in TechLead reviews that focus on code correctness.

**What to avoid:** Treating a TechLead MINOR item about INDEX.md as "documentation only" without fixing it during QA. INDEX.md drift is a first-class correctness issue when it misrepresents the implemented allow path — future developers and architects will be misled. Fix MINOR index items during QA pass.

**Pattern to repeat:** For features where the implemented approach deviated from the ADR's Alternatives "rejected" list (e.g., an approach was deferred until a later wave), verify the ADR's Alternatives section accurately calls it "deferred" not "rejected". A "rejected" label on an implemented approach is an integrity failure that erodes trust in the decision record.
