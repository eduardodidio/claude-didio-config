---
description: "[alias bmad] Registra um ajuste de rota (diff plano×realidade + ação corretiva)"
argument-hint: "<FXX> \"<descrição do desvio>\""
---

<!-- bmad-new: persona=AIE phase=downstream -->

# /bmad-correct-course — Course correction (AIE, downstream)

Você é o orquestrador de `/bmad-correct-course` no `claude-didio-config`.
Persona BMAD: **AIE**. Este comando roda **no contexto do prompt** (sem
subprocess).

## Step 1 — Resolva `<FXX>` e o desvio

Se `$ARGUMENTS` não trouxer um id de feature (`F` + dígitos), pergunte ao
usuário via `AskUserQuestion` ou liste `tasks/features/` (Bash `ls`) para
ajudar a escolher. Capture também a descrição do desvio (texto livre em
`$ARGUMENTS` ou pergunte ao usuário).

## Step 2 — Levante o plano vs. a realidade

Leia `tasks/features/<FXX>-*/<FXX>-README.md` para entender o plano original
(Waves, tasks, dependências, status declarado).

Compare com a realidade observada — use o que o usuário descreveu no
`$ARGUMENTS`/resposta, e opcionalmente verifique status real via `Bash`
(`git log`, `git status`, ou os arquivos da feature) para confirmar o que
mudou desde o plano.

## Step 3 — Registre o ajuste de rota

Escreva em `claude-didio-out/corrections/<FXX>-<YYYY-MM-DD>.md` (crie o
diretório se não existir — `mkdir -p claude-didio-out/corrections`), com a
data de hoje. Estrutura sugerida:

```markdown
# Course Correction — <FXX> (<data>)

## Plano original
<resumo do que o README/Waves previam>

## Realidade observada
<o que de fato aconteceu / divergência>

## Diff (plano x realidade)
<pontos de divergência específicos>

## Ação corretiva
<o que muda a partir de agora: reordenar Waves, atualizar dependências,
adicionar/remover tasks, etc.>
```

## Restrições

- Este comando **registra** o ajuste em `claude-didio-out/corrections/` —
  não edita os task files em `tasks/` nem dispara Waves/spawns. Se a ação
  corretiva exigir mudanças no plano, recomende ao usuário rodar
  `/bmad-create-story` ou `/plan-feature` separadamente.
- Não reimplemente lógica de planejamento do Architect — este comando é um
  registro de desvio + recomendação, não um re-plano automático.
