# Plano — integração seletiva de conceitos BMAD em `claude-didio-config`

**Status:** rascunho para discussão
**Data:** 2026-04-25
**Contexto:** usuário cursou BMAD em 2026-04 e listou 7 mecânicas. Já existe
acordo prévio (memória `user_bmad_course.md`) de que adoções são **aditivas**,
nunca substituem o pipeline atual `Architect → Developer → TechLead → QA`.

## TL;DR — minha recomendação

Não adotar BMAD inteiro. Pinçar 3 itens com alto impacto e baixo custo de
cerimônia (Tier 1), 3 itens opcionais (Tier 2), e dispensar 1 (Tier 3). A
ordem importa: Tier 1 sai primeiro porque destrava economia/qualidade dos
demais. Cada Tier 1 vira uma feature pequena (F09–F11), Tier 2 fica em
backlog até o Tier 1 mostrar resultado.

| # | Item BMAD do usuário                           | Veredito        | Onde entra                                |
|---|------------------------------------------------|-----------------|--------------------------------------------|
| 1 | `bmad-create-prd` (elicitation + party mode)   | Tier 1 parcial  | F11 — só elicitation; party mode descartado|
| 2 | `bmad_out` + arquivamento                      | Tier 1          | F09 — fundação para os outros              |
| 3 | `bmad-shard` + economia de tokens              | Tier 2          | F12 — após F09 estar de pé                 |
| 4 | `bmad-create-epics-and-stories`                | Tier 3 (skip)   | tasks já são stories; sem novo substantivo |
| 5 | `/bmad-check-implementation-readiness`         | Tier 1          | F10 — payback alto, custo baixíssimo       |
| 6 | TEA (test architect)                           | Tier 2 opt-in   | F13 — útil em downstream, não no framework |
| 7 | brainstorm → research → product-brief          | Tier 2          | F14 — vira 3 slash commands compostos      |

## Princípio que estou aplicando

> "Quanto mais especificado, melhor o resultado dos devs/QAs" tem teto.
> Especificação só compensa enquanto o esforço de escrever o spec é menor
> que o retrabalho que ele evita. Cerimônia além desse ponto é imposto.

O F08 é o exemplo do limite: brief de 280 linhas porque a feature é audit
+ correção crítica em hooks. Já a maioria das features pequenas (F02,
F03, F05) não precisaria de PRD, só de brief direto. Logo, o que adoto
do BMAD precisa ser **opt-in por tamanho**, nunca obrigatório.

---

## Tier 1 — adotar agora (3 features, ~5 dias)

### F09 — `bmad_out/` + `archive/` + scan-exclusion

**Por que primeiro:** destrava economia de tokens dos itens seguintes. O
problema real hoje: `tasks/features/F01-dashboard/` tem 14 task files, e
`F08` tem 11. Quando o Architect roda em qualquer feature nova, o filesystem
inteiro está visível para descoberta. Mesmo que ele não leia tudo, leituras
incidentais por glob/grep aumentam o custo.

**Escopo:**
- Criar `archive/features/` (gitignored mas não deletado).
- Script `bin/didio-archive-feature.sh <FXX>` move uma feature concluída
  (status QA passed) para `archive/features/`, preservando retrospective.md
  e logs no main repo.
- `.claude/settings.json` recebe `additionalDirectories` ou
  `ignorePatterns` para `archive/` (validar nome exato do campo no CLI atual).
- `.gitignore` ignora `archive/` por padrão. Opcional: branch
  `archive/features` se o usuário quiser histórico em git separado.
- Pasta `bmad_out/` reservada para drafts efêmeros (briefs preliminares
  de `/elicit-prd`, brainstorm/research outputs do Tier 2). Já gitignored.
- **Critério de aceitação:** archive de F01 reduz cold-start do Architect
  em ≥20% nos tokens da fase de descoberta — medir num spawn comparativo.

**O que NÃO entra nesta feature:** mover features ainda relevantes (F07,
F08), tocar em `memory/agent-learnings/` (essa fica viva), ou redesenhar
o layout `tasks/`.

### F10 — `/check-readiness <FXX>`

**Por que vale:** hoje o TechLead detecta gaps **depois** que Developers já
implementaram. Um audit pré-Wave roda em ~30s de Sonnet e captura erros de
plano cedo (AC sem teste correspondente, paralelismo violado, Wave 0 sem
permissões). Custo trivial, evita Wave inteira retrabalhada.

**Escopo:**
- Slash command `/check-readiness <FXX>` em `.claude/commands/`.
- Spawna agente `readiness` (novo prompt em `templates/agents/prompts/`)
  com Sonnet + effort medium.
- Lê `<FXX>-README.md` e cada `<FXX>-TYY.md`. Verifica:
  1. Cada AC do brief está coberto por ≥1 task.
  2. Cada task cita pelo menos um AC (rastreabilidade bidirecional).
  3. Tasks na mesma Wave não declaram os mesmos arquivos em
     "Implementation details".
  4. Wave 0 inclui tudo que Waves seguintes precisam (instalações,
     permissões, scaffolding).
  5. Cada task tem seção Testing não-vazia.
- Output: `tasks/features/<FXX>-*/readiness-report.md` com tabela
  PASS/FAIL e veredito final `READY | BLOCKED`.
- `/create-feature` (em `.claude/commands/create-feature.md`) passa a
  rodar `/check-readiness` automaticamente entre Architect e Wave 0;
  aborta se BLOCKED. Flag `--skip-readiness` para emergências.

**Risco:** falsos positivos (readiness reclama de coisa que está OK).
Mitigação: o agente só **reporta**, nunca edita; usuário decide se ignora.

### F11 — `/elicit-prd <FXX>` (PRD elicitation, sem party mode)

**Por que vale:** o brief F08 é tão bom porque o usuário pensou bastante.
Em features novas em projetos downstream (blind-warrior, escudo-do-mestre,
access-play-create) o Architect chuta gaps que um questionário estruturado
preencheria de antemão.

**Escopo:**
- Slash command `/elicit-prd <FXX> <título>`. Roda **interativamente**:
  faz 6–10 perguntas focadas (problema, persona, fora-de-escopo, riscos
  conhecidos, restrições técnicas, métrica de sucesso, dependências
  upstream, deadline). Não inventa perguntas — usa um template fixo.
- Output: `bmad_out/prd-drafts/<FXX>-prd.md` no formato existente
  `templates/docs/prd/template.md` (já existe, hoje órfão).
- Após confirmação do usuário, copia para
  `tasks/features/<FXX>-*/_brief.md` e `/plan-feature <FXX>` consome
  como hoje.
- **Importante:** elicitation é opt-in. `/plan-feature` continua
  aceitando descrição inline para features triviais.

**O que estou descartando do BMAD aqui:** *party mode* (PM + Architect +
Designer + QA brainstormando juntos). É caro (4× tokens) e o ganho
sobre um PM bem-feito + Architect é marginal nas features típicas do
usuário. Reabrir a discussão se aparecer feature realmente cross-functional
(ex: redesign de UX em access-play-create).

---

## Tier 2 — vale, mas só depois do Tier 1

### F12 — sharding de briefs + economia de tokens adicional

**Quando ativar:** quando um brief passa de 150 linhas ou feature tem >6
tasks. Caso contrário, sharding adiciona indireção sem ganho.

**Escopo proposto:**
- Architect, ao detectar brief grande, escreve `<FXX>-_brief/` como diretório:
  `00-overview.md`, `01-component-A.md`, etc.
- Cada task cita o(s) shard(s) que precisa em "Dev Notes" (ex: `Veja
  _brief/02-component-B.md`). Developer só lê o shard relevante.
- **Outras técnicas de economia que valem revisar nesta feature** (não
  todas viram código, algumas são doc/política):
  - Sumarização de Waves concluídas: ao terminar Wave N, escrever
    `<FXX>-wave-N-summary.md` com 10–20 linhas. Wave N+1 lê o summary,
    não os 5 task files completos.
  - Cache de leitura de `CLAUDE.md`: já é inserido pelo runtime; ok.
  - Effort por role (já entregue em F08) — manter.
  - Economy mode (já existe) — documentar quando usar (PoCs, drafts).
  - Memória via second-brain MCP em vez de `Read memory/...` (já existe;
    F06 entregou). Reforçar no prompt do Developer.

### F13 — TEA opcional (test architect role)

**Quando ativar:** features em projetos com domínio complexo (jogos,
acessibilidade, audio). No próprio framework, QA atual cobre.

**Escopo:** novo role `tea` em `templates/agents/prompts/`. Roda **uma vez**
entre Architect e Wave 0. Output: `<FXX>-test-plan.md` com fixtures,
harnesses, fronteira unit/integration/e2e, perf budgets. Tasks que
precisam de fixture específica passam a citar o test-plan. Liga via
`didio.config.json: { tea: { enabled: true } }`. Default off no framework,
default on no template usado por blind-warrior.

### F14 — brainstorm + research + product-brief (3 commands)

**Quando ativar:** decisões greenfield em projetos downstream. Pular
para evolução de features existentes.

- `/brainstorm <topic>` — Architect (ou PM) propõe 3–5 direções com
  trade-offs. Output em `bmad_out/brainstorms/`.
- `/research <topic>` — usa WebSearch + WebFetch p/ compilar precedentes,
  produtos comparáveis, blogs técnicos. Output em `bmad_out/research/`.
- `/product-brief <topic>` — funde os dois últimos drafts em um brief
  pronto para `/elicit-prd`. Output em `bmad_out/prd-drafts/`.
- Cada um é independente e composable. Usuário pula etapas que já tem.

---

## Tier 3 — descartar (com fundamento)

### Item 4 — epics & stories como substantivos novos

**Por que não:** `Feature → Wave → Task` já cobre. Tasks são literalmente
BMad stories (User Story + Dev Notes + Testing já no template). Adicionar
"Epic" entre Feature e Wave é cerimônia sem ganho enquanto features
cabem em uma rodada de Architect (todas hoje cabem).

**Quando reconsiderar:** se aparecer uma "iniciativa" multi-feature (tipo
"reescrever auth de access-play-create" cobrindo 4 features). Aí vira
um diretório `tasks/initiatives/Ixx/` com READMEs apontando para `Fxx`.
Não inventar agora.

### Party mode (subset do item 1)

Já justificado em F11. Custo alto, ganho marginal em features típicas do
usuário. Reabre só se F11 mostrar que elicitation single-PM tem gaps
sistemáticos.

---

## Sequência sugerida

```
Hoje:  finalizar F08 (effort + audit + sync)         ← em curso
                ↓
Sprint 1 (paralelizável):
  F09 (bmad_out/archive)        → 1 dia
  F10 (/check-readiness)        → 1 dia
                ↓
Sprint 2:
  F11 (/elicit-prd)             → 2 dias    ← consome F09 (bmad_out/)
                ↓
Avaliar:  rodar 2–3 features novas usando F09+F10+F11.
          Medir: tokens economizados, bugs de plano capturados,
          tempo de elicitation vs qualidade do brief resultante.
                ↓
Sprint 3 (decidir baseado na medição):
  F12 (sharding) e/ou F13 (TEA) e/ou F14 (brainstorm)
```

## O que precisa propagar para downstream (sync)

`didio-sync-project.sh` já merga blocos específicos. F09–F11 vão exigir:

- `.claude/commands/check-readiness.md` (novo) → propagar
- `.claude/commands/elicit-prd.md` (novo) → propagar
- `templates/agents/prompts/readiness.md` (novo) → propagar
- `bin/didio-archive-feature.sh` (novo) → propagar
- Bloco `bmad_out/`, `archive/` em `.gitignore` do downstream → merge não
  destrutivo (acrescenta linhas, não duplica)
- Possíveis ajustes em `.claude/settings.json` (ignorePatterns) → merge
  no padrão F04/F08 atual

**Importante:** F08 já está propagando `models[*].effort`. Aproveitar a
mesma rotina de merge ao introduzir F09+. Não reescrever sync.

## Riscos transversais

1. **Inflação de comandos.** `/plan-feature`, `/create-feature`,
   `/check-readiness`, `/elicit-prd`, `/brainstorm`, `/research`,
   `/product-brief` é muita coisa. Mitigação: docs claros +
   `didio menu` agrupando por fluxo (descobrir → planejar → executar).
2. **Drift entre framework e downstream.** Cada item novo é mais coisa
   pra `didio-sync-project.sh` mergar. Manter cobertura de teste no
   sync por bloco novo (já é convenção em F08-T0X).
3. **Adoção sem medição.** O risco maior é ativar tudo e nunca medir se
   ajudou. Sprint 2→3 tem gate explícito de medição antes de avançar.

## Próximo passo concreto

Escolher 1 das 3 features Tier 1 para abrir brief detalhado e rodar
`/plan-feature`. Recomendação: **F09 primeiro** porque:
- Menor risco (move arquivos, não muda comportamento de agente).
- Destrava economia que F11 e F12 vão alavancar.
- Resultado mensurável imediato (tokens cold-start).

Aguardando confirmação para escrever o `_brief.md` da F09.
