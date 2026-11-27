---
marp: true
theme: default
paginate: true
title: "claude-didio-config — Multi-Agent Orchestration Framework"
author: Eduardo Rutkoski Didio
---

# claude-didio-config

## Multi-Agent Orchestration for Claude Code

**Architecture / Leadership Forum**

Eduardo Rutkoski Didio | 2026

<!-- Speaker notes:
Hook: "What if your AI agents could learn from every project they've ever worked on?"
This framework turns Claude Code from a single-shot tool into an orchestrated
team of specialized agents that improve with every feature shipped.
-->

---

# The Problem

- Claude Code is powerful but **stateless** — no memory between sessions
- Complex features need **multiple specialized roles** working together
- No governance — who reviews the AI's architectural decisions?
- No visibility — what are the agents doing right now?
- Knowledge stays **trapped in one project** — same mistakes repeated across portfolio

<!-- Speaker notes:
Every team using Claude Code hits these walls. The framework solves all five.
-->

---

# The Solution: 4-Agent Workflow

```
Architect  -->  Developer x N  -->  TechLead  -->  QA
  (plan)        (implement)         (review)      (validate)
```

- **Architect** decomposes features into minimal tasks grouped in parallel Waves
- **Developer** implements each task in an isolated bash context
- **TechLead** reviews architecture, tests, diagrams
- **QA** validates end-to-end and fills test gaps
- **Retrospective** after every feature — agents literally learn

<!-- Speaker notes:
Wave 0 front-loads setup. Waves 1..N run Developers in parallel.
Each agent is a separate `claude -p` process — zero context pollution.
-->

---

# Agent Hierarchy: Black Hawk Squad

```
Black Hawk (strategic command + desktop assistant)
+-- Alpha (primary agent -- operator interface)
|   +-- Handler (tactical orchestration)
|   |   +-- GateKeeper (governance, bias detection)
|   +-- Bravo (CI/CD intelligence -- F36)
|   +-- Pipeline: Architect, Developer, TechLead, QA
|
Future: Charlie (monitoring), Delta (security)...
```

**Naming:** NATO phonetic alphabet + special operations terminology

<!-- Speaker notes:
"Black Hawk" = the squad. "Alpha" = strategic command. "Bravo" = intelligence.
Handler and GateKeeper negotiate up to 3 rounds before escalating.
The naming is intentional — it's a presentation-ready origin story.
-->

---

# Two-Board System

| War Room Board | Standard Board |
|----------------|---------------|
| Tactical, raw cards | Strategic, Kanban |
| Unstructured items | Prioritized features |
| Black Hawk Alpha triages | Handler executes |

```
Operator adds card --> Alpha triages --> Promote / Defer / Archive
                                            |
                                            v
                                    Standard Board feature
                                            |
                                            v
                                    Pipeline executes it
```

<!-- Speaker notes:
War Room = inbox for unstructured ideas. Alpha decides what becomes a feature.
Promotion creates the directory structure the Architect expects.
-->

---

# The Journey: F01 to F37

| Phase | Features | What shipped |
|-------|----------|-------------|
| **Backbone** | F01-F15 | Dashboard, spawn-agent, run-wave, guardrails, readiness, TEA |
| **Polish** | F16-F28 | Meeting-to-POC, meta-agents, rate-limit resume, multi-provider |
| **Corporate** | F29A-F34 | Rename, Kanban board, War Room, Desktop app, pipeline automation |
| **Intelligence** | F35-F37 | Promote fix, Bravo scanner, Knowledge Mesh |

**37 features shipped.** Each with TechLead review, QA validation, and retrospective.

<!-- Speaker notes:
Walk through the highlights. Emphasize the corporate standardization (F29A)
where all persona names were replaced with neutral Handler/GateKeeper.
-->

---

# DOB Benchmark

**Didio Orchestrator Benchmark** — objective comparison framework

- **12 evaluation dimensions**: decomposition, parallelism, isolation, tokens, coverage, diagrams, guardrails, resilience, learning, autonomy, time, rework
- **K=3 runs** per configuration for statistical significance
- **Regression gate** for CI — blocks if score drops >10%
- Compares **frameworks AND models** (not just one axis)

```bash
didio dob-run         # run benchmark
didio dob-score       # compute scores
didio dob-regression  # CI gate
```

<!-- Speaker notes:
DOB is how we measure ourselves. 12 dimensions, K=3 runs.
The regression gate prevents shipping a change that makes agents worse.
-->

---

# Black Hawk Bravo: Intelligence Agent

**4 modular scanners** running every 15 minutes:

| Scanner | Detects |
|---------|---------|
| Pipeline | Stuck, failed, paused, escalated pipelines |
| Flags | Stale flags, blocked features, flag storms |
| Token | Critical budget, high burn rate, stale data |
| Decisions | Low confidence, repeated challenges, escalation spikes |

**Output:** JSON report + War Room cards for Alpha to triage

<!-- Speaker notes:
Bravo is the first squad expansion. It's read-only — scans and reports.
Alpha triages Bravo's cards through the standard War Room flow.
-->

---

# Knowledge Mesh: Cross-Project Intelligence

```bash
didio mesh register ~/blind-warrior
didio mesh register ~/escudo-do-mestre-v1
didio mesh register ~/access-play-create

didio mesh sync      # broadcast learnings to all siblings
didio mesh query "caching pattern"  # search across all projects
```

Agents on Project A can now learn from Project B's mistakes.

<!-- Speaker notes:
This is the foundation for corporate-wide intelligence.
No MCP required — reads files directly. Works offline.
-->

---

# Guardrails

**Non-negotiable safety rules baked into CLAUDE.md:**

- Never `git rebase` on shared branches
- Never `git push --force` without asking
- Never `git add -A` — stage file by file
- Never commit secrets (`.env`, `*.pem`, `*.key`)
- Never disable auth/validation "just to make it work"
- Never modify CI/CD without explicit confirmation

**When in doubt: stop and ask the operator.**

<!-- Speaker notes:
These are in every project's CLAUDE.md. The agents follow them.
Cost of a pause is low. Cost of a destructive action is high.
-->

---

# Live Demo

## War Room Triage Flow

1. Add a card to the War Room
2. Black Hawk Alpha triages it
3. Promote to Standard Board
4. Pipeline executes the feature
5. Bravo monitors pipeline health

**See: `docs/presentation/demo-script.md`**

<!-- Speaker notes:
Switch to terminal. Follow the demo script step by step.
Total demo time: ~5 minutes.
-->

---

# What's Next

| Item | Status |
|------|--------|
| **Charlie** (monitoring agent) | Planned — NATO phonetic #3 |
| **Delta** (security agent) | Planned — NATO phonetic #4 |
| **MCP Corporate Integrations** | Planned — Jira, Confluence, Slack |
| **External VM Resources** | Planned — LLM/agent maintenance off-machine |
| **Multi-model DOB comparison** | In progress — Claude vs Codex vs Gemini |

<!-- Speaker notes:
The framework is designed to grow. Each new agent follows the same pattern.
MCP connectors will bring corporate data into the agent knowledge base.
-->

---

# Key Numbers

| Metric | Value |
|--------|-------|
| Features shipped | 37 |
| Agent roles | 10 (architect, developer, techlead, qa, readiness, tea, handler, gatekeeper, alpha, bravo) |
| E2E tests | 52+ across F35-F37 alone |
| Evaluation dimensions (DOB) | 12 |
| Guardrail rules | 14 |
| Mermaid diagrams | 40+ |
| ADRs | 16 |

---

# Thank You

**claude-didio-config**
github.com/eduardodidio/claude-didio-config

Eduardo Rutkoski Didio

<!-- Speaker notes:
Q&A time. Have the demo terminal ready for follow-up questions.
Mention that the framework is open source and can be installed in one line.
-->
