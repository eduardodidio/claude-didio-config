# QA Agent Learnings

## F02 — 2026-04-15

**What worked:** Tech Lead review flagged a missing test scenario and a canonical registry violation before QA ran — reading the review file first saved redundant discovery work.

**What to avoid:** Do not skip diffing the implemented test file against the task's "Test scenarios" section. Each listed scenario is a required test; if it's missing, create it — do not just report it. Also check canonical registry modules (e.g., `statusStyles.ts`) for functions that hardcode literal strings that should delegate to the registry map.

**Pattern to repeat:** Spy-based memo stability test: `vi.mock('@/lib/selectors', async (importOriginal) => { const actual = await importOriginal(); spy.mockImplementation(actual.fn); return { ...actual, fn: spy }; })` — then assert `spy.mock.calls.length` is stable after `rerender()` with same data reference. Clean, low-overhead useMemo correctness proof with no React Profiler boilerplate.

## F03 — 2026-04-14

**What worked:** Reading the Tech Lead review before running tests surfaced actionable follow-up items (stderr logging, diagram label fixes) that QA could fix directly rather than just report. This is the right division of labour: QA fixes what is clearly wrong; reports what is genuinely debatable.

**What to avoid:** Trusting that cross-stack acceptance criteria (e.g., `npm run test` inside a Python/bash feature) were run by the developer. Explicitly run and record every global criterion — especially ones that require tools outside the feature's primary stack.

**Pattern to repeat:** When a Tech Lead review returns APPROVED_WITH_FOLLOWUP, triage the follow-up items: fix code/diagram correctness issues directly during QA pass, record documentation-hygiene items in the QA report but don't block the verdict on them. Always re-run the full test suite after applying QA fixes to confirm nothing regressed. Check diagram labels against the actual implementation (not just the spec) — subtle vocabulary mismatches ("hash" vs "string compare") erode trust in documentation over time.
