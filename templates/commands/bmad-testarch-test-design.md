---
description: "[alias bmad] Re-rodar TEA para regenerar test plan — delega a /check-tests"
argument-hint: "<FXX>"
---

<!-- bmad-alias: delegates-to=/check-tests persona=QE -->

# /bmad-testarch-test-design — alias de /check-tests

Este é um **alias fino** do modo BMAD. Ele delega integralmente ao comando
`/check-tests` do didio. Persona BMAD: **QE**.

Execute exatamente o que `/check-tests $ARGUMENTS` faria — não reimplemente a
lógica. Carregue e siga `templates/commands/check-tests.md` com os mesmos
argumentos.
