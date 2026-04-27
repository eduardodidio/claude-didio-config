---
description: Funde brainstorm + research em brief pronto para /elicit-prd ou /plan-feature
argument-hint: ""
---

# /product-brief — Funde brainstorm + research em brief estruturado

Você é o orquestrador de `/product-brief` no `claude-didio-config`.

**Importante:** este command **não** spawna agente. Toda a interação roda no
seu próprio contexto. Use `AskUserQuestion` quando disponível.

---

## Step 1 — Liste artefatos disponíveis

Execute via ferramenta Bash:

```bash
ls -t claude-didio-out/brainstorms/*.md 2>/dev/null
```

Capture o resultado como `BS_FILES` (array, mais recentes primeiro; vazio se
o diretório não existir ou não houver `.md`).

```bash
ls -t claude-didio-out/research/*.md 2>/dev/null
```

Capture como `RS_FILES`.

---

## Step 2 — Pergunte ao usuário qual usar

Use `AskUserQuestion` para cada pergunta abaixo. Siga a ordem: primeiro
brainstorm, depois research, depois ID de feature.

### Pergunta 1 — Brainstorm

**Se `BS_FILES` não estiver vazio:**

Apresente via `AskUserQuestion` (kind: `select`):

> "Qual brainstorm consolidar?"

Opções: cada arquivo de `BS_FILES` no formato `<basename> — <data ISO do
mtime>` (derive o mtime via `stat -f "%Sm" -t "%Y-%m-%d" <path>` no macOS),
mais a opção `Nenhum (pular brainstorm)`.

**Se `BS_FILES` estiver vazio:**

Não apresente a pergunta. Registre `BS_CHOSEN=skipped`.

### Pergunta 2 — Research

**Se `RS_FILES` não estiver vazio:**

Apresente via `AskUserQuestion` (kind: `select`):

> "Qual research consolidar?"

Opções: cada arquivo de `RS_FILES` no mesmo formato, mais `Nenhum (pular
research)`.

**Se `RS_FILES` estiver vazio:**

Não apresente a pergunta. Registre `RS_CHOSEN=skipped`.

### Pergunta 3 — ID de feature

Via `AskUserQuestion` (kind: `freeform`):

> "Qual o ID da feature alvo? (ex: F15)"

Valide contra `^F[0-9]{2,3}$`. Se inválido, repergunte uma vez com aviso:

> "Formato inválido. Use F seguido de 2–3 dígitos (ex: F15). Qual o ID?"

Se ainda inválido após a segunda tentativa, use `F00` e avise o usuário:
`⚠️ ID inválido — usando F00 como fallback.`

---

## Step 3 — Detecte se /elicit-prd está disponível

Execute via Bash:

```bash
test -f .claude/commands/elicit-prd.md
```

- Exit 0 → `NEXT_STEP="/elicit-prd <FXX>"`
- Exit 1 → `NEXT_STEP="/plan-feature <FXX>"`

(Substitua `<FXX>` pelo ID coletado no Step 2.)

---

## Step 4 — Carregue o conteúdo dos arquivos escolhidos

**Se brainstorm foi escolhido (não skipped e não "Nenhum"):**

Leia o arquivo via ferramenta `Read`. Extraia:
- Título (primeira linha `#` ou `##`).
- Contexto (parágrafos antes do primeiro `### Direção`).
- Cada bloco `### Direção` (título + esforço + risco + recomendação se
  presente).

**Se research foi escolhido (não skipped e não "Nenhum"):**

Leia o arquivo via ferramenta `Read`. Extraia:
- Seção `## Sources` completa.
- Seção `## Key findings` completa.
- Seção `## Open questions` completa.

**Se ambos skipped:**

Pergunte ao usuário via `AskUserQuestion` (kind: `freeform`):
> "Descreva brevemente o problema ou oportunidade que motiva este brief:"

Use a resposta como `TOPIC_TEXT`.

---

## Step 5 — Crie o diretório de output

```bash
mkdir -p claude-didio-out/prd-drafts
```

---

## Step 6 — Escreva o brief

Caminho: `claude-didio-out/prd-drafts/<FXX>-brief.md`

Conteúdo obrigatório (5 seções literais, nessa ordem):

```markdown
# Product brief — <topic>

_Gerado em <YYYY-MM-DD> por /product-brief, alvo: <FXX>._

## Topic
<1 parágrafo descrevendo o problema/oportunidade. Derive do brainstorm se
presente, senão do research, senão use TOPIC_TEXT coletado acima.>

## Brainstorm directions chosen
<Se brainstorm escolhido: lista as direções com 1 linha cada (título +
esforço + risco). Indique qual é a recomendada com base nas trade-offs;
se não houver recomendação clara, pergunte ao usuário via AskUserQuestion
antes de escrever.>

_(skipped — sem brainstorm)_

## Research highlights
<Se research escolhido: copie `## Key findings` na íntegra e referencie
`## Sources` por link ou lista resumida.>

_(skipped — sem research)_

## Open questions
<Funde `## Open questions` do research (se presente) + perguntas levantadas
ao analisar o brainstorm. Se ambos skipped: inclua pelo menos a pergunta
"Qual é o problema concreto que motiva esse brief?".>

## Suggested next step
<NEXT_STEP do Step 3>
```

**Regras de preenchimento:**

- `## Brainstorm directions chosen`: use o bloco com conteúdo se brainstorm
  foi escolhido; caso contrário use apenas a linha `_(skipped — sem
  brainstorm)_`.
- `## Research highlights`: use o bloco com conteúdo se research foi
  escolhido; caso contrário use apenas a linha `_(skipped — sem research)_`.
- Nunca omita nenhuma das 5 seções — mesmo que o conteúdo seja o placeholder
  `_(skipped …)_`.
- Nunca copie para `tasks/features/` — output exclusivo em
  `claude-didio-out/prd-drafts/`.

---

## Step 7 — Reporte ao usuário

```
✅ Brief escrito: claude-didio-out/prd-drafts/<FXX>-brief.md
   Brainstorm: <basename ou skipped>
   Research:   <basename ou skipped>
🔁 Próximo passo: <NEXT_STEP>
```

---

## Caso degenerado — ambos skipped

Cenário válido: usuário roda `/product-brief` sem ter rodado `/brainstorm`
nem `/research`. Fluxo:

1. `BS_FILES` e `RS_FILES` ambos vazios → pula Perguntas 1 e 2.
2. Pergunta apenas ID de feature (Pergunta 3) e TOPIC_TEXT (Step 4).
3. Gera brief com `## Topic` preenchido via TOPIC_TEXT, ambas as seções de
   brainstorm e research com `_(skipped …)_`, e `## Open questions` com a
   pergunta padrão.

Sem error, sem stall.

---

## Regras invioláveis

- **NUNCA** spawne agente — não use ferramentas de spawn de sub-agente
  nem execute Waves via CLI. Ferramentas `Task`/`Agent` são proibidas.
- **NUNCA** copie para `tasks/features/` — product-brief é input para
  `/elicit-prd` ou entrada manual para `/plan-feature`; output **só** em
  `claude-didio-out/`.
- **SEMPRE** inclua as 5 seções literais (`## Topic`,
  `## Brainstorm directions chosen`, `## Research highlights`,
  `## Open questions`, `## Suggested next step`).
- **SEMPRE** detecte a presença de `elicit-prd.md` dinamicamente via
  `test -f .claude/commands/elicit-prd.md` — não hard-code a decisão.
- **SEMPRE** use `AskUserQuestion` para escolha de arquivos e ID de feature.
