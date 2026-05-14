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

### 💡 Dica: economize tokens usando o menu do terminal

O `/didio` dentro do Claude Code carrega ~260 linhas de prompt no contexto
**antes** de você escolher a opção — e ainda usa `AskUserQuestion`, que é
um round-trip do modelo. Para a maioria das ações (status, dashboard,
listar features, toggles de config) você não precisa do LLM.

**Zero tokens — rode no terminal:**

```bash
didio          # abre o menu (TUI puro em bash)
didio menu     # idem
```

O menu dispara a ação direto (ex: `didio dashboard`, abre docs, toggles)
e só invoca o Claude quando a ação **realmente** precisa de LLM (criar
feature, revisar branch, retro).

**Atalho de dentro do Claude Code:** digite `!didio` no prompt — o
prefixo `!` executa o shell direto na sessão. Mais barato que `/didio`,
mas a saída ainda entra no contexto do modelo. Use `/didio` apenas quando
a próxima ação já é LLM-heavy.

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

- **Rate-limit auto-resume (F22)**
  `didio spawn-agent` detecta rate-limit da Anthropic no JSONL e suspende
  o agente em vez de falhar. Use `--on-rate-limit=wait|schedule|fail-fast`
  e `DIDIO_CI=1` pra controlar o comportamento. `didio resume-pending`
  ou `didio spawn-agent --help` pra ver todas as flags.

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

## Rate-limit recovery

Quando o Anthropic API responde com rate-limit no meio de uma Wave,
o `didio spawn-agent` (a partir da F22) sabe se recuperar sem perder
trabalho. O comportamento é controlado pelo flag `--on-rate-limit`:

- **`--on-rate-limit=wait`** — bloqueia o spawn até o reset do
  rate-limit (lê o header `Retry-After`, dorme o tempo necessário +
  `DIDIO_RATE_LIMIT_MARGIN_SEC`, retoma). Use no fluxo interativo
  local: você está olhando o terminal e prefere esperar a continuar
  na mão.
- **`--on-rate-limit=schedule`** — marca a task como `pending`,
  escreve um stub em `_pending/`, e devolve exit=0 imediato. Use em
  CI ou orquestrações longas: o follow-up é feito por
  `didio resume-pending` quando o reset ocorrer. Para forçar schedule
  em CI: `DIDIO_ON_RATE_LIMIT=schedule`.
- **`--on-rate-limit=fail-fast`** — propaga o erro como exit=1 sem
  espera. **Default em CI** (quando `DIDIO_CI=1` ou `CI=1`). Use
  quando você quer que o pipeline pare e te avise (debugging, dry-runs).

O número de retries antes de o flag tomar efeito é controlado por
`--max-retries` (default 3). Veja
[ADR-0014: rate-limit auto-resume](../didio-second-brain-claude/docs/adr/0014-rate-limit-auto-resume.md)
no hub second-brain para a decisão arquitetural completa.
<!-- O link acima assume que ambos os repos são irmãos sob ~/. -->

### Troubleshooting: agent spawn falhou com exit 1

1. Cheque o JSONL do agent que falhou: `logs/agents/<role>-<feature>-<ts>.jsonl`.
2. Procure por `"hit your limit"` ou `"rate_limit"` no log:
   ```bash
   grep -E 'hit your limit|rate_limit' logs/agents/*.jsonl | tail -5
   ```
3. Se o termo aparecer, o agent foi rate-limited. Recupere com:
   ```bash
   didio resume-pending          # processa todos os pending
   ```
   ou re-spawne explicitamente:
   ```bash
   didio spawn-agent <role> --on-rate-limit=wait
   ```
4. Se o termo não aparecer, é outro tipo de erro — abra o JSONL
   manualmente e investigue.

### Variáveis de ambiente DIDIO_*

| Variável | Default | Descrição |
|---|---|---|
| `DIDIO_HOME` | `~/.claude-didio-config` | Path para o repositório do framework. |
| `DIDIO_CI` | `0` | Quando `1` (ou `CI=1`), força `--on-rate-limit=fail-fast` — o pipeline para com exit 1 em rate-limit. |
| `DIDIO_MAX_RETRIES` | `3` | Número de retries antes de aplicar `--on-rate-limit`. |
| `DIDIO_ON_RATE_LIMIT` | `wait` (ou `fail-fast` se `DIDIO_CI=1`) | Default global do flag `--on-rate-limit`. |
| `DIDIO_PLAN_ONLY` | `0` | Quando `1`, Architect roda em planning-only (não spawna Developer). |
| `DIDIO_SECOND_BRAIN_HOME` | (unset) | Path para o checkout local do `didio-second-brain-claude`. Toma precedência sobre heurísticas e `didio.config.json → second_brain.home`. |
| `DIDIO_INSTALL_SB` | (unset) | Controla o auto-install no `install.sh`: `yes`/`auto` força clone sem prompt; `no` pula sem prompt. Útil em CI. |

### Snippet `didio spawn-agent --help` (referência inline)

<!-- f24:help-snippet:start -->
```text
USAGE:
  didio spawn-agent <role> <feature> <task-file> [extra-prompt]

FLAGS:
  --on-rate-limit=<mode>   wait | schedule | fail-fast.
                           Default: wait (interactive),
                           fail-fast (when DIDIO_CI=1 or CI=1).
  --max-retries=<N>        Max retry attempts on rate-limit. Default: 3.
  --help, -h               Show this help and exit.

ENV VARS:
  DIDIO_HOME                       Framework install dir.
                                   Default: $HOME/.claude-didio-config.
  DIDIO_CI                         When =1, defaults --on-rate-limit to
                                   fail-fast. Same effect: CI=1.
  DIDIO_ON_RATE_LIMIT              Overrides flag default.
  DIDIO_MAX_RETRIES                Overrides --max-retries default (3).
  DIDIO_RATE_LIMIT_MARGIN_SEC      Extra seconds to wait past reset_at.
                                   Default: 60.
  DIDIO_RETRIES_SO_FAR             Internal counter; honored across
                                   exec re-spawns.
  AGENT_MODEL / AGENT_FALLBACK     Override model selection.

EXAMPLES:
  # Default invocation
  didio spawn-agent developer F23 tasks/features/F23/F23-T02.md

  # Schedule pending file on rate-limit (cron-friendly)
  didio spawn-agent developer F23 ./task.md --on-rate-limit=schedule

  # CI mode — fail-fast on rate-limit
  DIDIO_CI=1 didio spawn-agent developer F23 ./task.md
```
<!-- f24:help-snippet:end -->

> Este bloco é validado por `tests/F24-readme.sh`: se você editou o
> `--help` em `bin/didio-spawn-agent.sh`, regenere este bloco rodando
> `bin/didio spawn-agent --help` e copiando o output entre os
> marcadores HTML acima. O teste falha se divergir.

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

O framework integra-se ao MCP server irmão
[`didio-second-brain-claude`](https://github.com/eduardodidio/didio-second-brain-claude),
que centraliza "Prior Learnings" entre projetos e economiza tokens
reutilizando conhecimento entre features. **Medição (F06-benchmark)**:
~82 % de redução média no footprint de "Prior Learnings" por spawn
(developer 79 %, techlead 87 %, qa 77 %). Ver
`tests/F06-benchmark-results.md`. A integração é **opt-in** mas
**recomendada**.

#### Instalação automática

Durante `install.sh` (a partir de F24):

- Se `didio-second-brain-claude` ainda não estiver clonado, o instalador
  pergunta `"Clone it from github.com/eduardodidio/didio-second-brain-claude? [Y/n]"`.
  Default = `Y`.
- Para CI / pipes (sem TTY), o instalador **pula** silenciosamente.
  Force a instalação com `DIDIO_INSTALL_SB=yes`. Pule sem prompt com
  `DIDIO_INSTALL_SB=no`.
- Após o clone, o instalador escreve um bloco gerenciado no seu shell rc
  (`~/.zshrc` ou `~/.bashrc`) exportando:

  ```bash
  export DIDIO_SECOND_BRAIN_HOME="$HOME/didio-second-brain-claude"
  ```

Esse bloco é idempotente: re-rodar `install.sh` substitui o conteúdo
entre os markers (não duplica linhas).

#### Instalação manual (depois do fato)

Se você pulou no `install.sh` e mudou de ideia:

```bash
didio install-second-brain
# ou explicitamente:
bash ~/.claude-didio-config/bin/didio-install-second-brain.sh /path/where/i/want/it
```

O comando é idempotente — se o diretório já é um checkout git, ele faz
`git pull --ff-only` e sai 0.

#### Resolução de path (precedência)

Toda a stack do framework (smoke check, install skill, hooks) usa a
mesma ordem:

1. `$DIDIO_SECOND_BRAIN_HOME` (env var)
2. `didio.config.json → second_brain.home` (chave opcional)
3. Heurística: `$HOME/didio-second-brain-claude` → `$HOME/.claude-second-brain`

Vazio → second-brain é tratado como "não instalado".

#### Registro como MCP no Claude Code (passo manual)

Clonar o repo não registra a ferramenta no Claude Code automaticamente.
Confirme que `claude mcp list` mostra `second-brain` ativo. Siga as
instruções no README do
[`didio-second-brain-claude`](https://github.com/eduardodidio/didio-second-brain-claude)
para o `claude mcp add ...` final.

#### Configuração do `didio.config.json`

Adicione o bloco no `didio.config.json` do projeto:

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

#### Aviso sobre o template `templates/.claude/settings.json`

Esse arquivo é um **template** — não um arquivo de settings deployável.
Os 3 hooks do second-brain contêm o placeholder
`{{DIDIO_SECOND_BRAIN_HOME}}`, que é resolvido (ou removido) pela skill
`/install-claude-didio-framework` na materialização. Não copie o arquivo
diretamente pra `~/.claude/settings.json`.

#### Opt-out

- No fluxo do `/install-claude-didio-framework`, responda `no` à
  pergunta "Habilitar second-brain MCP?" — a skill remove as 3 entradas
  de hook do `.claude/settings.json` materializado.
- Pra silenciar avisos do smoke check em projetos onde você não usa:
  `"second_brain.enabled": false` no `didio.config.json`.

#### Smoke / testes

- `bin/didio-second-brain-smoke.sh` — preflight chamado por `run-wave`
- `tests/F06-integration-test.sh` — 19 cenários cobrindo config, smoke,
  sentinel substitution e dry-run da migração
- `tests/F06-token-benchmark.sh` — medição de delta de tokens

> ℹ️ **Nota sobre o `didio.config.json` deste repo**: o arquivo commitado
> na raiz tem `"enabled": true` porque o mantenedor dogfooda o framework
> com second-brain ligado. **Novos installs** recebem um config sem o
> bloco (via `templates/didio.config.json`) e caem no modo padrão
> automaticamente.
