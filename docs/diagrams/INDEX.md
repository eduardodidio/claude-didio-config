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

## F15 — Sensitive-file bypass for headless agents

| File | Owner task | What it shows |
|---|---|---|
| [F15-architecture.mmd](F15-architecture.mmd) | F15-T04 | Data-flow: spawn-agent → `claude -p` with `--allowedTools` → PreToolUse hook decision branches; positive (`templates/commands/`, with `.claude/commands` symlink) and negative (`.claude/settings.json`) paths; post-exec JSONL parser → exit override |
| [F15-journey.mmd](F15-journey.mmd) | F15-T04 | 5-swimlane flowchart (Operator / Wave-runner / Spawn-agent / Claude / Claude Code internals); happy path (Developer edits commands) and failure path (settings.json denied → exit ≠ 0 → wave-runner stops) |

## F16 — meeting-to-poc: ata de reunião → POC frontend rodável

| File | Owner task | What it shows |
|---|---|---|
| [F16-architecture.mmd](F16-architecture.mmd) | F16-T01 | `flowchart LR`: 7-step pipeline data-flow — `ata.md` → meeting-parser (LLM) → `manifest.json` → scaffold (cp template) → mock_gen → ui_gen → style_step → npm install → smoke (HTTP 200) → git commit → POC; side-inputs: `manifest.schema.json`, `templates/poc-vite-react/`, `--style-ref`; error exits 4/5/6/7 |
| [F16-journey.mmd](F16-journey.mmd) | F16-T01 | `flowchart TD` with 4 swimlanes (User, Slash command, Pipeline, meeting-parser); user journey from meeting end → write ata → `/poc-from-minutes` → AskUserQuestion → pipeline → POC; decision branches for invalid manifest (exit 4), npm install fail (exit 5), smoke fail (exit 6), git fail (exit 7) |

## F17 — Meta-Agent Performance Monitoring Harness

| File | Owner task | What it shows |
|---|---|---|
| [F17-architecture.mmd](F17-architecture.mmd) | F17-T09 | Data-flow: enabled meta-agents → log sources → metaSources loader → metaMetrics compute → CLI report + dashboard panel |
| [F17-journey.mmd](F17-journey.mmd) | F17-T11 | BPMN-style user journey: Handler→GateKeeper→Decision-Log→Harness loop; happy path + challenge/escalate branches |

## F29B — Pipeline Automation

| File | Owner task | What it shows |
|---|---|---|
| [F29B-architecture.mmd](F29B-architecture.mmd) | F29B-T10 | Pipeline execution flow: 8 stages (Handler Gate through Post-Review), signal files (pause/resume/cancel), state tracking, token budget integration, control commands, negotiation loop with governance logs |
| [F29B-journey.mmd](F29B-journey.mmd) | F29B-T10 | Operator journey: launch pipeline via /create-feature, negotiate Handler gate, execute waves with token budget checks, monitor via pipeline-status, pause/resume/cancel, post-review gate, success or escalation |

## F30 — Kanban Board, Governance Dashboard, Action System

| File | Owner task | What it shows |
|---|---|---|
| [F30-architecture.mmd](F30-architecture.mmd) | F30-T13 | Three-layer architecture: React Dashboard (KanbanBoard, Governance, FlagPanel, ActionButtons, hooks) -> File-Based Communication Layer (flags, actions, state, pipeline, meta-metrics) -> Shell Scripts (action-listener, flags-lib, learnings) -> Agent Pipeline (Architect, Developer, TechLead, QA) |
| [F30-journey.mmd](F30-journey.mmd) | F30-T13 | Operator journey: open dashboard -> view Kanban board -> check flags -> click action button -> confirmation (destructive) -> action JSON written -> listener processes -> board updates; alternate paths to Governance view (token budget, decision history, flag analytics) and card detail |

## F31 — War Room + Black Hawk Alpha Strategic Agent

| File | Owner task | What it shows |
|---|---|---|
| [F31-architecture.mmd](F31-architecture.mmd) | F31-T13 | War Room data flow (card sources, file layer, dashboard), Black Hawk Alpha triage flow (knowledge base, assessment, promotion bridge), agent hierarchy (Black Hawk Alpha above Handler/GateKeeper above standard pipeline), governance monitoring loop |
| [F31-journey.mmd](F31-journey.mmd) | F31-T13 | Four user flows: (1) operator adds card via dashboard, (2) operator adds card via CLI, (3) Black Hawk Alpha triages incoming cards (promote/defer/archive/needs_input), (4) governance monitoring detects patterns and creates strategic cards |

## F34 — Black Hawk Desktop Wiring

| File | Owner task | What it shows |
|---|---|---|
| [F34-architecture.mmd](F34-architecture.mmd) | F34-T07 | Data flow from pipeline scripts and flags through disk layer, Rust backend (commands, watcher, notifications), to React frontend hooks and views |
| [F34-journey.mmd](F34-journey.mmd) | F34-T07 | Operator journey: chat with Alpha via Claude CLI, view board with real pipeline state, notice tray alerts, click suggested actions |

## F35 — War Room Live Fire + Promotion Flow Fix

| File | Owner task | What it shows |
|---|---|---|
| [F35-architecture.mmd](F35-architecture.mmd) | F35-T07 | War Room data flow: card sources (CLI, agent, dashboard) -> card JSON -> triage CLI -> Black Hawk Alpha assessment -> promote bridge (directory + README creation) -> pipeline entry; includes defer/archive disposition paths |
| [F35-journey.mmd](F35-journey.mmd) | F35-T07 | Operator journey: add card -> review in dashboard/CLI -> trigger triage -> Alpha assesses -> review recommendation -> approve promote -> feature directory created -> run pipeline -> feature shipped; decision points (promote vs defer) and error branches (no assessment, rate limit) |

## F36 — Black Hawk Bravo Intelligence Agent

| File | Owner task | What it shows |
|---|---|---|
| [F36-architecture.mmd](F36-architecture.mmd) | F36-T10 | Intelligence data flow: data sources (pipeline state, flags, token budget, decisions, governance) -> Bravo scanners (4 parallel) -> report aggregator -> JSON report + War Room cards; Alpha observes Bravo's cards |
| [F36-journey.mmd](F36-journey.mmd) | F36-T10 | Operator journey: enable Bravo -> run monitor (once/continuous/dry-run) -> scanners detect anomalies -> report written -> cards created for findings -> Alpha triages; decision points (dry-run vs live, findings exist vs none) |

## F24 — auto-install second-brain

| File | Owner task | What it shows |
|---|---|---|
| [F24-architecture.mmd](F24-architecture.mmd) | F24-T01 | Component / data-flow: `$DIDIO_SECOND_BRAIN_HOME` + `second_brain.home` + heuristic dirs → `didio_second_brain_home/installed()` helper lib → consumers (`install.sh`, smoke, install skill, helper script) → `{{DIDIO_SECOND_BRAIN_HOME}}` placeholder in `templates/.claude/settings.json` → materialized `.claude/settings.json` (resolved or stripped) |
| [F24-journey.mmd](F24-journey.mmd) | F24-T02 | BPMN-style 3 swimlanes (User / install.sh / install skill); 4 paths: virgin install (offer + clone), opt-out (`DIDIO_INSTALL_SB=no` or `n`), opt-in skill answer (substitute placeholder), opt-out skill answer (strip 3 hook entries); all converge on a verified materialized project |
