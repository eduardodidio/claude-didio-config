# Skills Migration Map

Source → skill mappings for F01-T06 (additive seed of `skills/`).

Note: subagent skills use a `-agent` filename suffix to avoid collisions
with role-prompt skills sharing the same `name` (architect, developer, qa, techlead).

| Source | Skill | kind | targets |
|---|---|---|---|
| `.claude/commands/bmad-brainstorm.md` | `skills/bmad-brainstorm.md` | command | [claude, codex] |
| `.claude/commands/bmad-check-impl-readiness.md` | `skills/bmad-check-impl-readiness.md` | command | [claude, codex] |
| `.claude/commands/bmad-code-review.md` | `skills/bmad-code-review.md` | command | [claude, codex] |
| `.claude/commands/bmad-correct-course.md` | `skills/bmad-correct-course.md` | command | [claude, codex] |
| `.claude/commands/bmad-create-architecture.md` | `skills/bmad-create-architecture.md` | command | [claude, codex] |
| `.claude/commands/bmad-create-epics-and-stories.md` | `skills/bmad-create-epics-and-stories.md` | command | [claude, codex] |
| `.claude/commands/bmad-create-prd.md` | `skills/bmad-create-prd.md` | command | [claude, codex] |
| `.claude/commands/bmad-create-product-brief.md` | `skills/bmad-create-product-brief.md` | command | [claude, codex] |
| `.claude/commands/bmad-create-story.md` | `skills/bmad-create-story.md` | command | [claude, codex] |
| `.claude/commands/bmad-create-ux-design.md` | `skills/bmad-create-ux-design.md` | command | [claude, codex] |
| `.claude/commands/bmad-dev-story.md` | `skills/bmad-dev-story.md` | command | [claude, codex] |
| `.claude/commands/bmad-generate-project-context.md` | `skills/bmad-generate-project-context.md` | command | [claude, codex] |
| `.claude/commands/bmad-research.md` | `skills/bmad-research.md` | command | [claude, codex] |
| `.claude/commands/bmad-retrospective.md` | `skills/bmad-retrospective.md` | command | [claude, codex] |
| `.claude/commands/bmad-sprint-planning.md` | `skills/bmad-sprint-planning.md` | command | [claude, codex] |
| `.claude/commands/bmad-testarch-atdd.md` | `skills/bmad-testarch-atdd.md` | command | [claude, codex] |
| `.claude/commands/bmad-testarch-automate.md` | `skills/bmad-testarch-automate.md` | command | [claude, codex] |
| `.claude/commands/bmad-testarch-ci.md` | `skills/bmad-testarch-ci.md` | command | [claude, codex] |
| `.claude/commands/bmad-testarch-framework.md` | `skills/bmad-testarch-framework.md` | command | [claude, codex] |
| `.claude/commands/bmad-testarch-test-design.md` | `skills/bmad-testarch-test-design.md` | command | [claude, codex] |
| `.claude/commands/bmad.md` | `skills/bmad.md` | command | [claude, codex] |
| `.claude/commands/brainstorm.md` | `skills/brainstorm.md` | command | [claude, codex] |
| `.claude/commands/check-readiness.md` | `skills/check-readiness.md` | command | [claude, codex] |
| `.claude/commands/check-tests.md` | `skills/check-tests.md` | command | [claude, codex] |
| `.claude/commands/create-feature.md` | `skills/create-feature.md` | command | [claude, codex] |
| `.claude/commands/dashboard.md` | `skills/dashboard.md` | command | [claude, codex] |
| `.claude/commands/didio.md` | `skills/didio.md` | command | [claude, codex] |
| `.claude/commands/elicit-prd.md` | `skills/elicit-prd.md` | command | [claude, codex] |
| `.claude/commands/governance-review.md` | `skills/governance-review.md` | command | [claude, codex] |
| `.claude/commands/orchestrate.md` | `skills/orchestrate.md` | command | [claude, codex] |
| `.claude/commands/plan-feature.md` | `skills/plan-feature.md` | command | [claude, codex] |
| `.claude/commands/poc-from-minutes.md` | `skills/poc-from-minutes.md` | command | [claude, codex] |
| `.claude/commands/product-brief.md` | `skills/product-brief.md` | command | [claude, codex] |
| `.claude/commands/research.md` | `skills/research.md` | command | [claude, codex] |
| `agents/prompts/_checkpoint-block.md` | `skills/checkpoint-block.md` | role-prompt | [claude, codex] |
| `agents/prompts/architect.md` | `skills/architect.md` | role-prompt | [claude, codex] |
| `agents/prompts/developer.md` | `skills/developer.md` | role-prompt | [claude, codex] |
| `agents/prompts/meeting-parser.md` | `skills/meeting-parser.md` | role-prompt | [claude, codex] |
| `agents/prompts/narrative-designer.md` | `skills/narrative-designer.md` | role-prompt | [claude, codex] |
| `agents/prompts/qa.md` | `skills/qa.md` | role-prompt | [claude, codex] |
| `agents/prompts/readiness.md` | `skills/readiness.md` | role-prompt | [claude, codex] |
| `agents/prompts/t1000.md` | `skills/t1000.md` | role-prompt | [claude, codex] |
| `agents/prompts/t800.md` | `skills/t800.md` | role-prompt | [claude, codex] |
| `agents/prompts/tea.md` | `skills/tea.md` | role-prompt | [claude, codex] |
| `agents/prompts/techlead.md` | `skills/techlead.md` | role-prompt | [claude, codex] |
| `.claude/agents/architect.md` | `skills/architect-agent.md` | subagent | [claude] |
| `.claude/agents/developer.md` | `skills/developer-agent.md` | subagent | [claude] |
| `.claude/agents/qa.md` | `skills/qa-agent.md` | subagent | [claude] |
| `.claude/agents/techlead.md` | `skills/techlead-agent.md` | subagent | [claude] |
