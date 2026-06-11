---
description: "[BMAD] Selector /bmad <greenfield|brownfield> — encadeia upstream/downstream com pausa de fase e gates reusados"
argument-hint: "<greenfield|gf|brownfield|bf>"
---

# /bmad — Selector de modo BMAD

Você é o orquestrador de prompt do modo BMAD. `$ARGUMENTS` deve conter
`greenfield`, `gf`, `brownfield` ou `bf`.

Este comando **não reimplementa** nenhum sub-comando: ele apenas invoca, na
ordem certa, os comandos `/bmad-*` já existentes (que delegam aos comandos
base do didio). Ver `docs/diagrams/F27-journey.mmd` para a jornada completa.

## Passo 0 — Validar argumento

- Normalize `$ARGUMENTS`: `gf` → `greenfield`, `bf` → `brownfield`.
- Se `$ARGUMENTS` estiver vazio ou não for um desses 4 valores, use
  **AskUserQuestion** perguntando "Greenfield (produto novo) ou Brownfield
  (funcionalidade nova)?" com as duas opções, e use a resposta como modo.

## Passo 1 — UPSTREAM (depende do modo)

### Se `greenfield`:

Execute, em ordem, cada um dos seguintes comandos (passos `(opt)` são
oferecidos ao usuário, não forçados — pergunte antes de rodar):

1. `/bmad-generate-project-context`
2. `/bmad-brainstorm`
3. `/bmad-research` (opt)
4. `/bmad-create-product-brief`
5. `/bmad-create-prd`
6. `/bmad-create-ux-design`
7. `/bmad-create-architecture`
8. `/bmad-testarch-test-design`
9. `/bmad-create-epics-and-stories`

### Se `brownfield`:

Execute, em ordem:

1. `/bmad-generate-project-context`
2. `/bmad-create-prd`
3. `/bmad-create-ux-design`
4. `/bmad-create-architecture`
5. `/bmad-testarch-test-design`
6. `/bmad-create-epics-and-stories`

### Gate de readiness (opt, fronteira de fase)

Após o último passo do upstream, ofereça (opt) rodar
`/bmad-check-impl-readiness` (= `/check-readiness`, gate F10). Se o usuário
aceitar e o veredito for `BLOCKED`:

- **PARE o pipeline.** Mostre o path de `readiness-report.md` ao usuário e
  oriente a corrigir o plano antes de prosseguir.
- Não avance para o downstream.

Respeite `DIDIO_SKIP_READINESS=1` se já setado pelo usuário (não invente
novo bypass).

## Passo 2 — PAUSA de confirmação (obrigatória)

Ao fim do upstream (e do gate de readiness, se rodado), **PARE** e use
**AskUserQuestion** para confirmar explicitamente com o usuário se ele quer
iniciar o **DOWNSTREAM** agora — esta fase dispara Waves de desenvolvimento
(`dev-story`/`run-wave`) e portanto tem custo/efeitos maiores.

Nunca atravesse esta fronteira silenciosamente. Se o usuário responder não,
PARE aqui e informe que o plano está pronto para retomar depois com
`/bmad <gf|bf>` (ou diretamente pelos comandos `/bmad-*` do downstream).

## Passo 3 — DOWNSTREAM (compartilhado GF e BF)

Após confirmação, execute em ordem:

1. `/bmad-testarch-framework`
2. `/bmad-testarch-ci`
3. `/bmad-sprint-planning`
4. `/bmad-create-story`
5. `/bmad-testarch-atdd`
6. `/bmad-dev-story` (delega ao `run-wave` — gate TEA via `testarch-test-design`
   já rodou no upstream; respeite `DIDIO_SKIP_TEA=1` se setado)
7. `/bmad-code-review`
8. `/bmad-correct-course`
9. `/bmad-testarch-automate` (opt)
10. `/bmad-retrospective`

## Passo 4 — Log de execução (opcional)

Ao final, escreva (se possível) um resumo em
`claude-didio-out/bmad-runs/<gf|bf>-<YYYY-MM-DD>.md` contendo: modo
escolhido, passos executados, onde o pipeline pausou (se parou antes do
downstream) e o veredito do gate de readiness (se rodado).

## Regras

- Cada passo invoca o `/bmad-*` correspondente — que por sua vez delega ao
  comando base (`/brainstorm`, `/create-prd`, etc.). Não duplique a lógica
  de nenhum desses comandos aqui.
- Não reimplemente Gandalf (`t800`): ele já roda dentro de
  `/create-feature`/`/plan-feature`, chamados indiretamente pelos passos
  acima quando aplicável.
- Não reimplemente o gate TEA: `/bmad-testarch-test-design` delega a
  `/check-tests` (agente `tea`).
- Passos marcados `(opt)` são oferecidos ao usuário via pergunta simples,
  nunca forçados.
