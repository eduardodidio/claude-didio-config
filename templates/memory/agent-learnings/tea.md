# Agent Learnings — TEA

_Placeholder. QA acrescenta seções `## <FXX> — <YYYY-MM-DD>` aqui durante a
ceremony de retrospectiva (ver `templates/agents/prompts/qa.md`)._

## F13 — 2026-04-27

**What worked:** TEA boundary with QA is the load-bearing design decision — "do not write tests, do not replace QA" stated explicitly in the prompt prevents scope creep. The 7-section output contract tied 1:1 to `docs/F13-test-plan-spec.md` makes TEA output structurally verifiable by a smoke script without a live model run.

**What to avoid:** TEA writing actual test code (assertions, mocks, setup/teardown). That belongs to the Developer task; TEA only writes the plan (fixtures needed, harness type, perf budgets, mock rationale, test scenarios as prose). Any crossing of this line makes QA's job ambiguous.

**Pattern to repeat:** Task annotation (`**Test plan:** ver <FXX>-test-plan.md (fixtures: ...)`) at the end of TEA's run is the integration point with downstream Developer and QA agents — it makes the test plan discoverable without a directory scan. TEA must always edit task files to add this line after writing the plan.
