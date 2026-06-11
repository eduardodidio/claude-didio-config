---
description: "[alias bmad] Audit pré-Wave de uma feature planejada — delega a /check-readiness"
argument-hint: "<FXX>"
---

<!-- bmad-alias: delegates-to=/check-readiness persona=AIE -->

# /bmad-check-impl-readiness — alias de /check-readiness

Este é um **alias fino** do modo BMAD. Ele delega integralmente ao comando
`/check-readiness` do didio. Persona BMAD: **AIE**.

Execute exatamente o que `/check-readiness $ARGUMENTS` faria — não
reimplemente a lógica. Carregue e siga `templates/commands/check-readiness.md`
com os mesmos argumentos.
