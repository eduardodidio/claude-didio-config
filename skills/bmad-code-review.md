---
name: bmad-code-review
description: "[alias bmad] Revisão de código da branch (TechLead) — delega a /code-review"
kind: command
targets: [claude, codex]
argument-hint: "[ultra | <PR#>]"
---

<!-- bmad-alias: delegates-to=/code-review persona=QE -->

# /bmad-code-review — alias de /code-review

Este é um **alias fino** do modo BMAD. Ele delega integralmente ao comando
`/code-review` do didio. Persona BMAD: **QE**.

Execute exatamente o que `/code-review $ARGUMENTS` faria — não reimplemente
a lógica. O TechLead revisa a implementação seguindo
`agents/prompts/review-tasks.md` com os mesmos argumentos.
