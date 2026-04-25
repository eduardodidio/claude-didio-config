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
