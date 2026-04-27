# Diagrams Index

All diagrams are [Mermaid](https://mermaid.js.org/) `.mmd` files.

## F01 — didio monitoring dashboard

| File | Owner task | What it shows |
|---|---|---|
| [F01-dashboard-architecture.mmd](F01-dashboard-architecture.mmd) | F01-T09 | Component tree: App → Router → MainLayout → {Sidebar, Outlet, Footer} → views |
| [F01-dashboard-data-flow.mmd](F01-dashboard-data-flow.mmd) | F01-T06 | `state.json` → `fetchState` → React Query → `useDidioState` → views |
| [F01-dashboard-routes.mmd](F01-dashboard-routes.mmd) | F01-T14 | Route map for `/`, `/features`, `/agents`, `/easter-eggs` |

## F02 — Features view refactoring

| File | Owner task | What it shows |
|---|---|---|
| [F02-architecture.mmd](F02-architecture.mmd) | F02-T04 | Module dependencies: `Features.tsx` → `statusStyles.ts`, `Progress`, `selectors.ts`, `useDidioState`; external deps `@radix-ui/react-progress`, `framer-motion` |
| [F02-journey.mmd](F02-journey.mmd) | F02-T04 | User journey through the Features view: open page → polling → derived state → cards, progress bars, status chips |

## F03 — Log watcher & state.json improvements

| File | Owner task | What it shows |
|---|---|---|
| [F03-architecture.mmd](F03-architecture.mmd) | F03-T01 | Component/data-flow: `didio-log-watcher.sh` internals — load agents, README mtime cache, compute_feature, no-op guard, atomic write to `state.json` |
| [F03-journey.mmd](F03-journey.mmd) | F03-T01 | Watcher tick lifecycle — from tick start through feature enumeration, README parsing, JSON hash check, and conditional state write |

## F04 — Bootstrap sync to downstream projects

| File | Owner task | What it shows |
|---|---|---|
| [F04-architecture.mmd](F04-architecture.mmd) | F04-T01 | Data-flow: `templates/` + `SKILL.md` → `didio-sync-project.sh` (validate, tag, diff, copy, merge, section-sync, skip) → downstream projects |
| [F04-journey.mmd](F04-journey.mmd) | F04-T01 | Operator journey: invoke sync-all → load project list → per-project tag + copy loop → protected file checks |

## F05 — Sync downstream propagation

| File | Owner task | What it shows |
|---|---|---|
| [F05-architecture.mmd](F05-architecture.mmd) | F05-T01 | Data-flow: framework `templates/` → `didio-sync-all.sh` → `didio-sync-project.sh` → 5 downstream projects (with rollback tag creation) |
| [F05-journey.mmd](F05-journey.mmd) | F05-T01 | Operator journey: trigger sync-all, per-project tag + copy loop, all-ok check, evidence review; failure branch shows rollback with `git reset --hard` |

## F06 — Second-brain memory integration

| File | Owner task | What it shows |
|---|---|---|
| [F06-architecture.mmd](F06-architecture.mmd) | F06-T11 | Two-track data-flow: spawn sentinel → prompt → agent picks memory_search (second-brain on) or Read (fallback); QA retro mirrors into second-brain via memory_add |
| [F06-journey.mmd](F06-journey.mmd) | F06-T11 | Operator journey: run-wave → smoke preflight → per-task spawn with sentinel substitution → agent applies learnings → QA closes loop with memory_add |

## F07 — Session guard (token budget + pause/resume)

| File | Owner task | What it shows |
|---|---|---|
| [F07-architecture.mmd](F07-architecture.mmd) | F07 | Component & data-flow: PreToolUse hook → session-guard → budget state → pause/resume cycle |
| [F07-journey.mmd](F07-journey.mmd) | F07 | User journey: launch feature → budget consumed → graceful pause → resume on next session |

## F08 — Agent runtime (spawn-agent model + effort)

| File | Owner task | What it shows |
|---|---|---|
| [F08-architecture.mmd](F08-architecture.mmd) | F08 | Agent runtime: spawn-agent with model + effort config, session-guard hooks observing budget, downstream sync propagating models/effort block |
| [F08-journey.mmd](F08-journey.mmd) | F08 | Operator journey for F08 agent runtime changes |

## F09 — Output isolation + feature archival

| File | Owner task | What it shows |
|---|---|---|
| [F09-architecture.mmd](F09-architecture.mmd) | F09-T01 | Data-flow: agents write drafts to `claude-didio-out/`, active work in `tasks/features/`, archive trigger moves to `archive/features/` + retro copy to `memory/retrospectives/`; downstream sync branch |
| [F09-journey.mmd](F09-journey.mmd) | F09-T01 | BPMN-style: operator requests archive → eligibility check (qa PASSED + 30d) → copy retro → mv feature; branches for `--list`, `--dry-run`, `--force`, and ineligible error |

## F10 — Pre-Wave readiness gate

| File | Owner task | What it shows |
|---|---|---|
| [F10-architecture.mmd](F10-architecture.mmd) | F10-T01 | Data-flow: `/check-readiness` → readiness agent reads `<FXX>-README.md` + tasks → 5-check loop → `readiness-report.md` with verdict READY/BLOCKED |
| [F10-journey.mmd](F10-journey.mmd) | F10-T01 | Pipeline gate: `/create-feature` Architect → Step 1.5 readiness → Wave 0 (READY) or STOP (BLOCKED); bypass via `DIDIO_SKIP_READINESS=1` |

## F11 — Interactive PRD elicitation

| File | Owner task | What it shows |
|---|---|---|
| [F11-architecture.mmd](F11-architecture.mmd) | F11-T01 | Data-flow: `/elicit-prd` slash command → 8 fixed questions via AskUserQuestion → draft PRD in `claude-didio-out/prd-drafts/` → optional copy to `_brief.md` |
| [F11-journey.mmd](F11-journey.mmd) | F11-T01 | Operator journey: invoke `/elicit-prd` → answer questions → review draft → confirm copy → feed `/plan-feature` |

## F12 — Brief sharding + token economy

| File | Owner task | What it shows |
|---|---|---|
| [F12-architecture.mmd](F12-architecture.mmd) | F12-T01 | Component/data-flow: Architect sharding decision (enabled, lines ≥ threshold, tasks ≥ threshold) → `_brief/` dir or single `_brief.md`; Wave summary loop: post-wave TechLead writes `FXX-wave-N-summary.md` → carry-forward to Wave N+1 |
| [F12-journey.mmd](F12-journey.mmd) | F12-T01 | BPMN-style user journey: large feature → 3 decision gateways (sharding.enabled, brief_lines_threshold, task_count_threshold) → sharded or flat execution → Wave summaries → delivered |

## F13 — TEA (Test Architect) opcional pre-Wave

| File | Owner task | What it shows |
|---|---|---|
| [F13-architecture.mmd](F13-architecture.mmd) | F13-T01 | Sequence: Architect → tea.enabled check → spawn TEA → test-plan written → tasks annotated → Wave 0; branches for false (silent skip) and DIDIO_SKIP_TEA=1 (warned skip) |
| [F13-journey.mmd](F13-journey.mmd) | F13-T01 | BPMN-style flowchart with User/Orchestrator/TEA/FS swimlanes; shows opt-in, bypass, and error paths |

## F14 — Brainstorm + Research + Product-Brief commands

| File | Owner task | What it shows |
|---|---|---|
| [F14-architecture.mmd](F14-architecture.mmd) | F14-T01 | Three independent slash commands: `/brainstorm` → directions matrix; `/research` → market+technical brief; `/product-brief` → fuses prior outputs into ready brief |
| [F14-journey.mmd](F14-journey.mmd) | F14-T01 | Greenfield discovery flow: brainstorm directions → research deepens → product-brief fuses → feeds `/elicit-prd` or `/plan-feature` |
