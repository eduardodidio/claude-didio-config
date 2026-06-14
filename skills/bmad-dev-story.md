---
name: bmad-dev-story
description: "[alias bmad] Implementa uma Wave de tasks (developer) — delega ao spawn run-wave"
kind: command
targets: [claude, codex]
argument-hint: <FXX> <wave>
---

<!-- bmad-alias: delegates-to=run-wave persona=AIE -->

# /bmad-dev-story — alias de run-wave

Este é um **alias fino** do modo BMAD. Ele delega integralmente à execução
de Wave do didio. Persona BMAD: **AIE**.

Execute `didio run-wave $ARGUMENTS` (feature e número da wave informados em
`$ARGUMENTS`), que spawna o agente **developer** para implementar as tasks
`Status: planned` daquela Wave — não reimplemente a lógica do developer
nem do run-wave.
