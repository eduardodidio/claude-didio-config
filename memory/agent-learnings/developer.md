# Developer Agent Learnings

## F02 — 2026-04-15

**What worked:** Wave dependency order (Wave 0 deps → Wave 1 parallel modules → Wave 2 integration) prevented file conflicts. `featureMap` (Map pre-computed in `useMemo`) is better than inline `features.find()` inside render loops.

**What to avoid:** When a module is introduced as a canonical style registry (e.g., `STATUS_STYLE`), all functions in that module must read from it — not re-declare the same literal strings. Grep for hardcoded Tailwind color strings in new registry modules before submitting. Also: task files list test scenarios as a checklist, not as illustrative examples — implement every scenario.

**Pattern to repeat:** Pre-compute a `Map<key, value>` in `useMemo` to replace O(n) `array.find()` calls inside JSX maps. When using `asChild` with Framer Motion inside a Radix primitive, animate `width` instead of `transform` to avoid conflicts with Radix's internal transform injection — add a brief comment explaining why.

## F03 — 2026-04-14

**What worked:** Choosing Option A (persistent Python process) for the no-op guard compounds with the README cache — both optimisations survive across ticks in the same process. Module-level cache dict + `_clear_cache()` helper is the right Python pattern for process-lifetime caching that is also test-friendly.

**What to avoid:** Bare `except Exception: pass` in any persistent/daemon-style loop — a watcher that silently fails is indistinguishable from a healthy idle watcher; always log to stderr. Leaving `[ ]` checkboxes unchecked in task files (recurred from F02). Diagram labels that describe the spec design rather than the actual implementation — when you choose a simpler approach (string compare instead of MD5 hash), update the diagrams.

**Pattern to repeat:** Persistent-process refactor (bash thin-launcher `exec python3 …`): separates stateless bash setup from stateful Python loop cleanly, and eliminates the need for external `.prev_hash` temp files. ADR "reject" documents with explicit, enumerated reasoning are as valuable as "accept" ADRs. Always include cross-stack acceptance criteria (`npm run test`) explicitly in the integration test script or benchmark results — do not assume they pass by inference.
