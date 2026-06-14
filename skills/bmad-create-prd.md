---
name: bmad-create-prd
description: "[alias bmad] PRD elicitation interativa — delega a /elicit-prd"
kind: command
targets: [claude, codex]
argument-hint: <FXX> "<título>"
---

<!-- bmad-alias: delegates-to=/elicit-prd persona=PB -->

# /bmad-create-prd — alias de /elicit-prd

Este é um **alias fino** do modo BMAD. Ele delega integralmente ao comando
`/elicit-prd` do didio. Persona BMAD: **PB**.

Execute exatamente o que `/elicit-prd $ARGUMENTS` faria — não reimplemente a
lógica. Carregue e siga `templates/commands/elicit-prd.md` com os mesmos
argumentos.
