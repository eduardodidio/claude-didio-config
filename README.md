# claude-didio-config

Framework opinativo pro Claude Code. Instala num projeto em segundos,
traz workflow de 4 agentes (Architect → Developer → TechLead → QA) em
Waves paralelas, dashboard de monitoramento (**Didio Agents Dash**),
guardrails de segurança e cerimônia de retrospectiva que faz os agentes
aprenderem com o que deu certo e errado.

**Copyright © 2026 Eduardo Rutkoski Didio.**

---

## Instalação em 1 linha (recomendado)

Dentro do projeto onde você quer instalar, abra o Claude Code e cole:

```
Claude, instale o framework de https://github.com/eduardodidio/claude-didio-config
no meu projeto atual.
```

Pronto. O Claude clona o repo, roda o `install.sh`, executa o bootstrap
interativo (`/install-claude-didio-framework`), cria `CLAUDE.md`, docs/,
tasks/, agents/, `.claude/`, `memory/agent-learnings/` e te mostra o menu
inicial.

### Instalação manual (avançado)

```bash
curl -sSL https://raw.githubusercontent.com/eduardodidio/claude-didio-config/main/install.sh | bash
cd meu-projeto && claude
> /install-claude-didio-framework
```

---

## Rodando o dashboard localmente

O dashboard é servido por `didio dashboard` a partir de `dashboard/dist/`,
com um symlink `state.json → logs/agents/state.json` gerado pelo watcher.
Essa é a forma correta — `npm run dev` (Vite) **não funciona direto**
porque o fallback SPA do Vite devolve `index.html` pra `./state.json`,
quebrando o parse e travando o carregamento.

```bash
# build único (quando os arquivos do dashboard mudarem)
cd dashboard && npm install && npm run build && cd ..

# subir o dashboard (porta default 7777)
./bin/didio dashboard
# ou noutra porta:
./bin/didio dashboard 8080
```

Abra http://localhost:7777/. O watcher regenera `logs/agents/state.json`
a cada 1s a partir dos JSONL — a UI faz polling e atualiza sozinha.

Se a porta já estiver ocupada (`Address already in use`), provavelmente
já tem um `didio dashboard` rodando. Use `lsof -iTCP:7777 -sTCP:LISTEN`
pra confirmar antes de matar o processo.

---

## Inspirações e refinamentos

O `claude-didio-config` se inspira fortemente no **BMAD method** para
elicitação de PRD, sharding e auditoria de readiness, mas cada
estratégia foi adaptada às necessidades específicas dos projetos
downstream do usuário (`blind-warrior`, `escudo-do-mestre-v1`,
`access-play-create`, `mellon-magic-maker`). A intenção não é portar
BMAD verbatim — é destilar o que funciona e integrar ao workflow
Architect → Developer → TechLead → QA já existente, sem prefixar
nada com `bmad-` no framework (comandos, diretórios e arquivos
mantêm a identidade `didio`).

Estratégias adotadas e em estudo:

- **Output isolation** (`claude-didio-out/`) — F09 `[ativo]` —
  rascunhos, brainstorms e research vão pra um diretório efêmero,
  gitignored, fora do scan automático dos agentes.
- **Arquivamento de features concluídas** (`archive/`) — F09
  `[ativo]` — feature QA-aprovada migra de `tasks/features/` para
  `archive/features/`; aprendizado fica em `memory/retrospectives/`.
  Reduz custo de descoberta dos próximos agentes spawnados.
- **PRD elicitation antes de planejar** — F11 `[em planejamento]` —
  comando interativo que coleta requisitos com o usuário antes de
  invocar o Architect, gerando rascunhos em
  `claude-didio-out/prd-drafts/`.
- **Readiness audit pré-Wave** — F10 `[em planejamento]` — checa o
  brief antes de disparar Waves; impede execução de tasks com
  contexto incompleto.
- **Sharding de briefs grandes** — F12 `[backlog]` — quebra briefs
  longos em pedaços focados antes do Architect, espelhando a prática
  BMAD de dividir PRDs em épicos.

Cada item linka, quando ativo, para o `_brief.md` da feature
correspondente em `tasks/features/` ou `archive/features/`.

---

## Primeiros passos — menu `/didio`

Depois de instalado, dentro do Claude Code:

```
/didio
```

O menu te dá 1-clique pra:

- 🆕 **Criar feature** — dispara Architect → Waves → TechLead → QA
- 🐛 **Corrigir bug** — feature curta com 1 Wave
- 🔍 **Revisar código** — só o TechLead sobre os commits da branch
- 📊 **Status** — mostra runs recentes e feature atual
- 🖥️ **Abrir dashboard** — `didio dashboard` no navegador
- 📚 **Ver docs** — `docs/`, ADRs, PRDs, diagramas
- 🎓 **Retrospectiva manual** — consolida learnings dos agentes

No terminal, o equivalente é `didio menu` (ou `didio` sem argumentos).

---

## Prompts pré-configurados (copie e cole)

### Criar nova feature

```
Claude, leia CLAUDE.md e crie a feature F0X: <descrição curta>.
Use o workflow didio: Architect → Waves → TechLead → QA.
Ao terminar, atualize o README.md do projeto com o que foi entregue.
```

### Corrigir um bug

```
Claude, temos um bug: <descrição + passos pra reproduzir>.
Crie uma feature curta com 1 Wave. Rode Developer, TechLead e QA.
```

### Revisar código (só TechLead)

```
Claude, rode apenas o agente TechLead sobre os commits desta branch
e me dê um verdict com issues BLOCKING / IMPORTANT / MINOR acionáveis.
```

### Planejar antes de codar (plan mode)

```
Claude, entre em plan mode e explore <área/feature>. Quero um plano com:
contexto, arquivos críticos, passos numerados, verificação end-to-end
e riscos. Não implemente nada ainda.
```

### Retrospectiva manual de feature

```
Claude, rode cerimônia de retrospectiva da feature F0X.
Consolide learnings por role em memory/agent-learnings/<role>.md
e escreva tasks/features/F0X/retrospective.md.
```

### Atualizar diagramas

```
Claude, atualize os diagramas Mermaid em docs/diagrams/ pra refletir
o estado atual do código. Inclua arquitetura e jornada do usuário (BPMN).
```

> ⚠️ **Importante:** antes de iniciar uma nova feature, rode `/clear`
> pra limpar o contexto. Contexto contaminado leva a decisões ruins e
> queima tokens à toa.

---

## O que você ganha

- **Workflow de 4 agentes em Waves paralelas**
  Architect decompõe a feature em tasks mínimas agrupadas em Waves.
  Wave 0 front-loada setup/deps. Waves 1..N rodam Developer em paralelo.
  TechLead revisa. QA valida ponta-a-ponta.

- **Contexto isolado por agente**
  Cada agente é lançado em um novo processo bash (`claude -p`). Zero
  poluição de contexto entre Waves. Tudo streamado em JSONL pra auditoria.

- **Dashboard de monitoramento — Didio Agents Dash**
  Vite + React + shadcn/ui dark obsidian. Mostra Waves, agentes rodando,
  duração, frases temáticas por franquia. Clique numa linha do agente
  pra abrir o log em tempo real estilo terminal. `didio dashboard`.

- **Cerimônia de retrospectiva por feature**
  Ao fim de cada feature, QA consolida aprendizagens por role em
  `memory/agent-learnings/<role>.md`. Cada agente lê o próprio arquivo
  de aprendizagens ao iniciar — os agentes literalmente melhoram a cada
  feature que passa.

- **Guardrails de segurança no CLAUDE.md**
  Sem `rebase` em branches compartilhadas, sem `--force`, sem
  `--no-verify`, sem `git add -A`, sem commitar secrets. Regras claras
  que o Claude Code segue sem precisar lembrar toda vez.

- **Diagramas obrigatórios por feature**
  Architect gera pelo menos 2 diagramas Mermaid por feature:
  **arquitetura** (component/data-flow) e **jornada de usuário**
  (BPMN-style). Ficam em `docs/diagrams/` como documentação viva.

- **README auto-atualizado**
  Toda feature que entrega valor atualiza o `README.md` do projeto
  automaticamente. Você nunca mais esquece de documentar.

- **Easter eggs temáticos por franquia**
  Cada role tem uma franquia padrão: Architect = Star Wars,
  Developer = Senhor dos Anéis, TechLead = Naruto, QA = Pokémon.
  Totalmente customizável em `easter-eggs.json`.

- **Highlander mode (opt-in)** — _equivalente a Auto Mode on_
  Ativa o Auto Mode nativo do Claude Code via
  `permissions.defaultMode: "auto"` e mantém um allow-list liberal como
  fallback. Waves rodam sem prompts. Só use em projetos sandboxed.

---

## Layout do projeto depois do bootstrap

```
meu-projeto/
├── CLAUDE.md                       (instruções + guardrails)
├── README.md                       (auto-atualizado por feature)
├── docs/
│   ├── adr/                        Architecture Decision Records
│   ├── prd/                        Product Requirements Documents
│   ├── diagrams/                   Mermaid (arquitetura + jornada)
│   └── README.md
├── tasks/
│   └── features/                   Manifests + task files por feature
├── agents/
│   ├── orchestrator.md
│   ├── workflows/
│   └── prompts/                    architect, developer, techlead, qa
├── memory/
│   └── agent-learnings/            ← aprendizagens por role (retro)
├── logs/agents/                    (gitignored) JSONL + meta.json
└── .claude/
    ├── settings.json
    ├── commands/                   /didio, /create-feature, /dashboard
    └── agents/
```

---

## Customizando as franquias dos easter eggs

Edite `easter-eggs.json` na raiz do projeto (criado no bootstrap).
Defaults:

| Role       | Franquia padrão      |
|------------|----------------------|
| Architect  | Star Wars            |
| Developer  | Senhor dos Anéis     |
| TechLead   | Naruto               |
| QA         | Pokémon              |

Pra trocar, edite `role_mapping`:

```json
"role_mapping": {
  "architect": ["dragon_ball_z"],
  "developer": ["mario", "one_piece"],
  "techlead":  ["dnd"],
  "qa":        ["kimetsu_no_yaiba"]
}
```

Cada role pode ter 1 ou mais franquias — o sistema escolhe aleatório
dentro da lista. Desabilita geral com `export DIDIO_EASTER_EGGS=0`.

---

## Status

**Phase 1 (backbone)** ✅ install, spawn-agent, run-wave, templates,
prompts, slash commands, project models, Highlander mode.

**Phase 2 (Didio Agents Dash)** ✅ dashboard Vite+React+shadcn com
polling de `state.json`, view de agentes com log modal terminal-style,
view de phrases por franquia.

**Phase 3 (polish + guardrails + UX)** ✅ menu `/didio`, guardrails no
CLAUDE.md, cerimônia de retrospectiva, diagramas obrigatórios (arq +
jornada BPMN), prompts pré-configurados, rebranding "Didio Agents Dash".

---

## Memória dos agentes (learnings entre features)

A cada feature, o QA roda a cerimônia de retrospectiva e consolida
aprendizagens por role em `memory/agent-learnings/<role>.md`. No próximo
spawn, cada agente lê o próprio arquivo antes de começar — é assim que os
agentes melhoram a cada feature.

Há **dois modos** de memória, e o framework decide automaticamente
baseado no que está disponível:

### Modo padrão (sem MCP) — funciona out-of-the-box

Esse é o modo que você ganha ao rodar `/install-claude-didio-framework`.
Nenhum setup extra. O `didio.config.json` criado pelo bootstrap **não tem**
o bloco `second_brain` — os helpers default pra `enabled=false`,
`fallback_to_local=true`, e os prompts leem direto o arquivo local.

- ✅ Zero dependências externas
- ✅ Histórico inspecionável via `git log memory/agent-learnings/`
- ⚠️ O agente carrega o arquivo inteiro a cada spawn (cresce com o tempo;
  na prática só vira problema depois de dezenas de features)
- ⚠️ Cross-project sharing é manual via `bin/didio-sync-project.sh`

**Nada mais a fazer.** Pula a próxima seção.

### Modo second-brain (opt-in, avançado)

A partir da F06, o framework pode integrar com o MCP server do projeto
irmão
[`didio-second-brain-claude`](https://github.com/eduardodidio/didio-second-brain-claude)
pra substituir a leitura do arquivo inteiro por uma busca segmentada:
cada spawn só carrega os ~10 snippets relevantes à feature atual.
**Medição (F06-benchmark)**: ~82 % de redução média no footprint de
"Prior Learnings" por spawn (developer 79 %, techlead 87 %, qa 77 %).
Ver `tests/F06-benchmark-results.md`.

**Pré-requisitos:**

1. Instalar e configurar o MCP server seguindo o README do
   [`didio-second-brain-claude`](https://github.com/eduardodidio/didio-second-brain-claude).
2. Confirmar que `claude mcp list` mostra `second-brain` ativo.

**Adicione o bloco no `didio.config.json` do projeto:**

```json
"second_brain": {
  "enabled": true,
  "fallback_to_local": true
}
```

- `enabled=true` + MCP online → agentes chamam
  `mcp__second-brain__memory_search` antes de começar.
- `enabled=false` **ou** MCP offline + `fallback_to_local=true` → agentes
  voltam a ler `memory/agent-learnings/<role>.md` localmente.
- `fallback_to_local=false` + MCP offline → `didio-second-brain-smoke.sh`
  aborta o wave com exit 2 (preflight rígido).

**Migração one-shot** (ingere learnings locais já existentes):

```bash
DIDIO_MIGRATE_DRY=1 bin/didio-migrate-learnings.sh   # inspecionar
bin/didio-migrate-learnings.sh                        # rodar de verdade
```

**Retrospectiva**: na cerimônia do QA (`templates/agents/prompts/qa.md`,
passo 3b), cada lesson é **espelhada** pro second-brain via `memory_add`
— mantendo arquivo local + memória MCP em sync. A ADR
`docs/adr/F06-memory-location.md` documenta a decisão.

**Smoke / testes:**

- `bin/didio-second-brain-smoke.sh` — preflight chamado por `run-wave`
- `tests/F06-integration-test.sh` — 19 cenários cobrindo config, smoke,
  sentinel substitution e dry-run da migração
- `tests/F06-token-benchmark.sh` — medição de delta de tokens

> ℹ️ **Nota sobre o `didio.config.json` deste repo**: o arquivo commitado
> na raiz tem `"enabled": true` porque o mantenedor dogfooda o framework
> com second-brain ligado. **Novos installs** recebem um config sem o
> bloco (via `templates/didio.config.json`) e caem no modo padrão
> automaticamente.
