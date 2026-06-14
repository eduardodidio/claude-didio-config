---
name: bmad-sprint-planning
description: "[alias bmad] Ordena stories/tasks de uma feature planejada em ordem de execução (Waves) — gera sprint plan"
kind: command
targets: [claude, codex]
argument-hint: "<FXX>"
---

<!-- bmad-new: persona=AIE phase=downstream -->

# /bmad-sprint-planning — Sprint planning (AIE, downstream)

Você é o orquestrador de `/bmad-sprint-planning` no `claude-didio-config`.
Persona BMAD: **AIE**. Este comando roda **no contexto do prompt** (sem
subprocess) e é **read-only** sobre `tasks/` — nunca edita task files.

## Step 1 — Resolva `<FXX>`

Se `$ARGUMENTS` não trouxer um id de feature (`F` + dígitos), pergunte ao
usuário via `AskUserQuestion` ou liste `tasks/features/` (Bash `ls`) para
ajudar a escolher.

## Step 2 — Leia o README da feature

Leia `tasks/features/<FXX>-*/<FXX>-README.md` (use `Glob` para resolver o
caminho exato). Este arquivo é a fonte de verdade: contém as Waves já
declaradas pelo Architect e a lista de tasks de cada Wave (ids, títulos,
dependências, status).

Não leia os task files individuais (`<FXX>-TYY.md`) a menos que o README não
tenha detalhe suficiente sobre dependências — nesse caso leia apenas o
cabeçalho (`Wave:`, `Depends on:`, `Status:`) dos arquivos necessários.

## Step 3 — Monte o plano de sprint

A partir das Waves e tasks do README, produza uma ordem de execução:

- Preserve o agrupamento em Waves já existente (não reordene entre Waves —
  isso já reflete dependências resolvidas pelo Architect).
- Dentro de cada Wave, liste as tasks na ordem do README, com seu status
  atual (`planned` / `done` / etc.).
- Marque tasks `done` como concluídas e destaque a próxima Wave pendente
  como "próxima a rodar via `didio run-wave <FXX> <N>`".

## Step 4 — Escreva o sprint plan

Escreva em `claude-didio-out/sprint-plans/<FXX>-<YYYY-MM-DD>.md` (crie o
diretório se não existir — `mkdir -p claude-didio-out/sprint-plans`), com a
data de hoje. Estrutura sugerida:

```markdown
# Sprint Plan — <FXX> (<data>)

## Ordem de execução

### Wave 0
- [ ] <FXX>-T01 — <título> (status: planned)
...

### Wave 1
...

## Próximo passo
`didio run-wave <FXX> <N>` (Wave <N> é a próxima pendente)
```

## Restrições

- **Nunca** use `Edit`/`Write` sobre arquivos em `tasks/` — apenas `Read`/
  `Glob` para esse diretório. O único `Write` deste comando é em
  `claude-didio-out/sprint-plans/`.
- Não dispare `didio run-wave` nem qualquer spawn — este comando é só
  planejamento/leitura.
- Não reimplemente o pipeline Architect→Waves; o sprint plan é um espelho
  de leitura do README, reordenado para consumo humano.
