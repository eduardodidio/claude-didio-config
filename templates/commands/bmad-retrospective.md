---
description: "[alias bmad] Roda a cerimônia de retrospectiva (QA) — delega ao spawn qa-retro"
argument-hint: <FXX>
---

<!-- bmad-alias: delegates-to=qa-retro persona=QE -->

# /bmad-retrospective — alias de qa-retro

Este é um **alias fino** do modo BMAD. Ele delega integralmente à cerimônia
de retrospectiva embutida no agente QA. Persona BMAD: **QE**.

Pergunte o id da feature (`<FXX>`) se não vier em `$ARGUMENTS` e execute:

`didio spawn-agent qa <FXX> tasks/features/<FXX>*/<FXX>-README.md` com a
instrução extra "rode APENAS a cerimônia de retrospectiva" — o mesmo padrão
da opção 7 do menu `/didio`. Não reimplemente a lógica da retrospectiva nem
crie um agente novo.
