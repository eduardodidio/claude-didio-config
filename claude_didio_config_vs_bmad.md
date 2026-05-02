# `claude-didio-config` (+ second-brain) **vs.** BMad puro

**Status:** comparação prática, baseada em medições deste repo
**Data:** 2026-05-02
**Audiência:** quem precisa decidir qual stack usar para um projeto novo (ou
quando trocar) e justificar a escolha com números.

> **Resumo em uma linha.** BMad é uma metodologia completa (PRD → epics →
> stories → dev) com cerimônia rica. `claude-didio-config` é um runtime
> opinado de 4 agentes em Waves paralelas que **incorporou seletivamente**
> as 5 técnicas do BMad com maior payback (elicitation, readiness, sharding,
> TEA, brainstorm/research/product-brief), descartou as de cerimônia alta
> (party mode, camada Epic), e adicionou coisas que BMad não tem (memória
> compartilhada via second-brain MCP, dashboard, retrospectivas que voltam
> para o prompt do próximo spawn, guardrails de segurança).

---

## 1. TL;DR — matriz de decisão

| Critério                             | BMad puro                          | claude-didio-config + second-brain        |
|--------------------------------------|------------------------------------|-------------------------------------------|
| Filosofia                            | Especificação rica antes de codar  | Especificação proporcional ao tamanho     |
| Camadas de planejamento              | PRD → Epic → Story → Dev          | Brief → Task (Waves)                      |
| Execução                             | Sequencial por agente              | **Wave 0 setup + Waves 1..N em paralelo** |
| Agentes simultâneos (party mode)     | PM + Architect + QA + Designer     | Não (descartado por custo/ganho)          |
| Memória entre features               | Sem mecanismo nativo               | `memory/agent-learnings/<role>.md` + MCP  |
| PRD elicitation interativa           | ✅ Nativo                          | ✅ `/elicit-prd` (sem party mode)         |
| Readiness audit pré-implementação    | ✅ Nativo                          | ✅ `/check-readiness`                     |
| Sharding de briefs grandes           | ✅ Nativo                          | ✅ Auto > 150 linhas / > 6 tasks          |
| TEA (test architect)                 | ✅ Nativo                          | ✅ Opt-in via `tea.enabled`               |
| Brainstorm + research + brief        | ✅ 3 papéis distintos              | ✅ 3 slash commands compostos             |
| Dashboard de observabilidade         | ❌                                 | ✅ Vite + React (`didio dashboard`)       |
| Retrospectiva → prompt do próximo agente | ❌ (é só doc)                  | ✅ Lido no spawn seguinte                 |
| Guardrails (no `--force`, no secrets) | Implícitos                        | ✅ Hard-coded em `CLAUDE.md`              |
| Easter eggs / DX                     | ❌                                 | ✅ (cosmético, mas reduz fadiga)          |
| Curva de adoção                      | Alta (vocabulário novo: PM, Epic…) | Média (4 papéis + 7 slash commands)       |
| Quando o spec é overkill             | Difícil escapar do pipeline        | Brief inline + 1 Wave resolve             |

---

## 2. O que muda concretamente

### 2.1. Vocabulário e camadas

**BMad puro:**
```
Discovery → PRD → Epic → Story → Dev → QA
```

**claude-didio-config:**
```
(opcional: brainstorm/research/product-brief) → /elicit-prd → /plan-feature
   → /check-readiness → Wave 0 (setup) → Waves 1..N (Developer paralelo)
   → TechLead → QA → retrospectiva
```

A camada **Epic** foi explicitamente descartada (Tier 3 do plano de
integração) — `Feature → Wave → Task` cobre o mesmo papel sem inventar
substantivo novo. Tasks já são literalmente BMad stories: trazem
`User Story + Dev Notes + Testing` no template.

### 2.2. Party mode — descartado

O *party mode* do BMad (PM + Architect + Designer + QA brainstormando
juntos no mesmo turno) custa ≈ 4× mais tokens por rodar em paralelo no
mesmo contexto. O ganho marginal sobre **um PM bem-feito + Architect**
não justifica o custo nas features típicas. `claude-didio-config`
mantém só a elicitation single-PM (`/elicit-prd`), e reabre party mode
apenas se aparecer feature realmente cross-functional (UX redesign,
acessibilidade ampla).

### 2.3. Memória — diferença estrutural

BMad puro **não tem** mecanismo de memória entre features. Cada PRD
recomeça do zero.

`claude-didio-config` tem **dois modos**:

- **Local (default)**: cada role lê `memory/agent-learnings/<role>.md`
  no spawn. O QA, na cerimônia de retrospectiva, anexa lessons.
- **Second-brain MCP (opt-in)**: substitui o read do arquivo por uma
  `mcp__second-brain__memory_search` segmentada — ~10 snippets
  relevantes em vez do arquivo inteiro.

### 2.4. Paralelismo

BMad executa stories em sequência. `claude-didio-config` agrupa tasks
em Waves; a Wave 0 front-loada deps/perms/scaffolding, e as Waves 1..N
disparam vários `claude -p` em paralelo (cada Developer em processo
isolado, contexto limpo, JSONL streamado para o dashboard). Quando a
feature tem 5–8 tasks independentes, o ganho de wall-clock é real.

---

## 3. Medições de tokens — onde está o ganho de cada um

> Todas as medições abaixo são **deste repositório**, registradas em
> `docs/F09-measurement-raw/`, `docs/F12-shard-measurement.md` e
> `tests/F06-benchmark-results.md`. Proxy de tokens = bytes / 4 quando
> indicado; medições reais usam `usage` do JSONL do `claude -p`.

### 3.1. Memória de roles (second-brain MCP) — **ganho do claude-didio-config**

Atividade: spawn de 1 agente (developer/techlead/qa) lendo *Prior
Learnings* antes de começar.

| Role       | Local bytes | Local tokens | Second-brain tokens | Δ %        |
|------------|-------------|--------------|---------------------|------------|
| developer  | 3 451       | 862          | 180                 | **−79 %**  |
| techlead   | 5 612       | 1 403        | 180                 | **−87 %**  |
| qa         | 3 222       | 805          | 180                 | **−77 %**  |
| **média**  |             |              |                     | **−82 %**  |

> Fonte: `tests/F06-benchmark-results.md`. Critério de aceite (≥ 50 %)
> passou folgado.

**Onde o BMad puro perde:** não há equivalente. Seria preciso recriar
manualmente a lição no PRD seguinte ou aceitar a regressão.

### 3.2. Sharding de brief grande (F12) — **ganho mútuo**

Atividade: Developer recebe brief de feature grande (F08, 277 linhas
originais).

| Fixture                    | Linhas | Tokens (proxy ×4) | Δ          |
|----------------------------|--------|-------------------|------------|
| A — brief não-shardado     | 277    | ~ 1 108           | baseline   |
| B — `_brief/` + 1 shard    |  99    | ~   396           | **−64 %**  |

> Fonte: `docs/F12-shard-measurement.md`.

**Onde os dois ganham:** sharding é técnica do BMad, e
`claude-didio-config` só dispara automático acima de 150 linhas ou 6
tasks (`didio.config.json: sharding.brief_lines_threshold = 150`).
**Diferença:** no BMad é workflow manual; no `claude-didio-config` é
heurística automática — features pequenas escapam da indireção.

### 3.3. Readiness audit pré-Wave (F10) — **ganho mútuo, mas amortizado diferente**

Atividade: agente `readiness` (Sonnet, effort medium) audita o brief +
todas as tasks **antes** da Wave 0 disparar.

| Estado                                             | Custo                        |
|----------------------------------------------------|------------------------------|
| `/check-readiness` (Sonnet medium, 30 s)           | ~ 4–8 k tokens               |
| Re-spawn de Wave inteira por bug de plano detectado tarde | ~ 30–80 k tokens (3 devs em paralelo + TechLead + QA) |
| **Payback**                                        | **5×–20×** quando bloqueia 1 falso positivo de plano |

A mecânica é a mesma do BMad. **Diferença prática:** integração no
`/create-feature` torna o audit obrigatório (com `--skip-readiness`
para emergências). No BMad é etapa manual — fácil de pular.

### 3.4. Archive de features concluídas (F09) — **ganho operacional, não computacional**

Atividade: cold-start de Architect num repo com 8 features concluídas
ainda em `tasks/features/`.

| Estado                              | Tokens totais | Δ            |
|-------------------------------------|---------------|--------------|
| Antes (F01 + F02 ativas)            | 45 326        | baseline     |
| Depois (F01 + F02 em `archive/`)    | 45 312        | **−14 (−0,03 %)** |

> Fonte: `docs/F09-scan-exclusion-check.md` + `docs/F09-measurement-raw/`.

**Lição honesta:** `tasks/` já estava em `.gitignore`, então ripgrep
nunca enxergou. O ganho real do archive é **operacional** (`ls` mais
limpo, separação semântica done vs. active), não de tokens. BMad teria
o mesmo ganho operacional. Esta linha está aqui justamente para mostrar
que **nem todo conceito do BMad gera economia de tokens neste setup** —
medir antes de adotar é a regra.

### 3.5. Effort por role (F08) — **ganho do claude-didio-config**

`didio.config.json` atribui `effort: medium` para developer/techlead/qa
e `opus` para architect. Isso é granularidade que BMad puro não expõe —
no BMad você escolhe modelo por papel, mas não nível de esforço por
papel + fallback. Em features triviais, `economy: true` empurra todo
mundo para `haiku`. O ganho é variável e dominado pela escolha do
usuário, mas a **tipificação por role** evita regressão (developer
nunca cai para opus por acidente).

### 3.6. Resumo dos ganhos por atividade

| Atividade                                 | claude-didio-config + second-brain | BMad puro      |
|-------------------------------------------|------------------------------------|----------------|
| Ler memory/learnings antes de spawnar     | **−82 %** vs. arquivo local        | sem mecanismo  |
| Brief grande para Developer               | −64 % via sharding (auto)          | −64 % via sharding (manual) |
| Audit pré-Wave                            | 5×–20× payback (integrado em `/create-feature`) | 5×–20× payback (manual) |
| Archive de features done                  | −0,03 % (ruído)                    | −0,03 % (ruído) |
| Cerimônia para feature trivial            | brief inline + 1 Wave              | PRD/Epic/Story sempre |
| Party mode (4 agentes paralelos)          | descartado                         | disponível, custa ~4× |
| Wall-clock de feature com 6 tasks paralelizáveis | Waves rodam concorrente     | Stories em série |

---

## 4. Quando usar `claude-didio-config` (+ second-brain)

Use quando **pelo menos 2** dos pontos abaixo se aplicam:

1. **Você roda mais de uma feature por semana no mesmo projeto.** O
   ganho de memória entre features (−82 % no carregamento de
   learnings) só amortiza com volume. Em projeto de 1 feature/mês a
   memória compete com cerimônia de cuidar dela.
2. **Tem tasks paralelizáveis dentro da mesma feature.** Se a feature
   sempre vira 1 ou 2 PRs sequenciais, Waves não dão ganho de wall-clock.
3. **Você quer observabilidade visual** (dashboard) ou auditoria por
   JSONL — ex: dogfood, repos compartilhados, projetos onde precisa
   explicar o que cada agente fez.
4. **Você opera múltiplos projetos similares** (`blind-warrior`,
   `escudo-do-mestre-v1`, `access-play-create`, `mellon-magic-maker`) e
   quer compartilhar lições via second-brain MCP em vez de copiar/colar
   memory entre repos.
5. **Você valoriza guardrails default.** O `CLAUDE.md` já bloqueia
   `--force`, `--no-verify`, `git add -A`, commitar secrets. Em BMad
   puro isso é convenção do time.
6. **A feature é pequena/média na maioria das vezes.** Aqui o brief
   inline + 1 Wave + retrospectiva resolve sem invocar PRD/Epic/Story.
   A heurística de 150 linhas / 6 tasks ativa as ferramentas pesadas só
   quando precisa.

**Cenários típicos onde brilha:**

- Bug fix urgente: `/didio` → "🐛 Corrigir bug" → 1 Wave → QA passou.
- Feature de tamanho médio (3–5 tasks paralelizáveis) num repo já
  com `memory/agent-learnings/` populado.
- Repos downstream que herdam o pipeline via `didio-sync-project.sh`.
- Greenfield em projeto multi-modal (audio + a11y + game) onde TEA
  opt-in faz diferença e o prompt do TEA é compartilhado entre repos.

---

## 5. Quando usar BMad puro

Use quando **pelo menos 1** dos pontos abaixo se aplica:

1. **Sua organização já adota BMad.** Trocar a metodologia inteira só
   para usar `claude-didio-config` raramente compensa — pegue o que
   ressoa (sharding, readiness) e adapte na sua stack.
2. **Discovery realmente cross-functional** com PM, Designer e QA
   contribuindo no mesmo turno. *Party mode* é a feature distintiva do
   BMad e a única que `claude-didio-config` explicitamente recusa.
3. **Iniciativa multi-feature de longo prazo** (rewrite de auth, swap
   de stack inteira) onde a camada **Epic** entre PRD e Story tem
   conteúdo real — coordenação de várias features sob um tema. Em
   `claude-didio-config` isso é "abrir um diretório
   `tasks/initiatives/Ixx/`", o que ainda não foi feito; BMad já tem
   convenção pronta.
4. **Você não quer rodar JS/TS** (dashboard React) ou não quer um MCP
   server adicional para memória.
5. **Você precisa de PRD/PM document como entregável formal** para
   stakeholders externos (cliente, compliance). O BMad gera artefato
   pronto; `claude-didio-config` gera brief mais enxuto, otimizado para
   alimentar agentes — não para ler na sala de reunião.
6. **Equipe nova em código assistido por IA.** A cerimônia explícita do
   BMad ajuda a estabelecer rituais antes de otimizar para velocidade.

**Cenários típicos onde brilha:**

- Discovery de produto novo com 3+ stakeholders.
- Migração de plataforma onde a camada Epic ancora 6+ features.
- Squad que está aprendendo IA-assisted dev e precisa do andaime
  pesado para criar disciplina antes de cortar cerimônia.

---

## 6. Decisões explícitas que `claude-didio-config` tomou em relação ao BMad

| Decisão                                              | Veredito | Razão                                                                 |
|------------------------------------------------------|----------|----------------------------------------------------------------------|
| `bmad-create-prd` (elicitation)                      | **Adotado parcialmente** (F11) | Single-PM; party mode descartado por custo                  |
| `bmad_out/` + arquivamento                           | **Adotado** (F09) | Renomeado `claude-didio-out/`; ganho operacional comprovado          |
| `bmad-shard` + economia                              | **Adotado** (F12) | Auto-trigger por threshold; gain de 64 % medido                       |
| `bmad-create-epics-and-stories`                      | **Descartado** | Feature → Wave → Task já cobre; Epic sem conteúdo novo                |
| `/bmad-check-implementation-readiness`               | **Adotado** (F10) | Custo trivial, payback 5×–20×                                         |
| TEA (test architect)                                 | **Adotado** (F13) opt-in | Útil em downstream multi-modal; off por default no framework          |
| brainstorm + research + product-brief                | **Adotado** (F14) | 3 slash commands composable, não 3 papéis novos                       |
| Party mode                                           | **Descartado** | ~4× custo, ganho marginal nas features típicas                        |
| Camada Epic entre Feature e Story                    | **Descartado** | Reabrir só para iniciativas multi-feature                             |

> Fonte canônica: `docs/bmad-integration-plan.md`.

---

## 7. Trade-offs honestos do `claude-didio-config`

1. **Inflação de slash commands.** Já tem `/plan-feature`,
   `/create-feature`, `/check-readiness`, `/elicit-prd`, `/brainstorm`,
   `/research`, `/product-brief`, `/check-tests`, `/dashboard`,
   `/didio`. O menu `/didio` agrupa, mas o user precisa lembrar dos
   fluxos.
2. **Drift framework ↔ downstream.** Cada item novo precisa de merge
   em `didio-sync-project.sh` para propagar para os 4 projetos
   irmãos. Ônus contínuo.
3. **Risco de adoção sem medição.** O plano de integração tem gates
   explícitos de medição (Sprint 2 → Sprint 3) — ignorar isso é como
   adotar BMad inteiro sem questionar.
4. **Memória cresce sem ground-truth.** O `memory/agent-learnings/`
   pode acumular lessons que viraram obsoletas. A retrospectiva escreve,
   mas não revisita. Mitigação parcial: second-brain MCP permite busca
   semântica e remoção; modo local não.
5. **Dashboard exige Node/Vite build.** Adiciona dep de tooling que
   BMad puro não tem. Em projeto Python-only isso pesa.
6. **`tasks/` no `.gitignore` esconde plano do git.** Decisão
   intencional (manifests são efêmeros), mas significa que o plano da
   feature não vive no histórico — vive em `archive/features/` e em
   memory/retrospectives. BMad por default versiona PRDs e stories.

---

## 8. Recomendação resumida

- **Comece com `claude-didio-config` se** você quer um runtime opinado
  com dashboard, paralelismo de Waves, e memória entre features —
  aceitando a curva dos ~7 slash commands e o overhead de Vite.
- **Comece com BMad puro se** você precisa de cerimônia de produto
  formal, party mode real, ou já tem squad acostumada com PRD/Epic/Story.
- **Não combine os dois no mesmo repo.** Os conceitos sobrepostos
  (sharding, readiness, elicitation) ficam confusos com dois donos.
  Escolha um e, se for `claude-didio-config`, saiba que ele já trouxe
  o que vale do BMad — sem a cerimônia pesada e sem o vendor-lock no
  vocabulário.

> **Fontes desta comparação:** `docs/bmad-integration-plan.md`,
> `tests/F06-benchmark-results.md`, `docs/F12-shard-measurement.md`,
> `docs/F09-scan-exclusion-check.md`, `docs/F09-measurement-raw/`,
> `didio.config.json`, `README.md`.
