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

- **Highlander mode (opt-in)**
  `.claude/settings.json` com `permissions.allow` liberal. Waves rodam
  sem prompts. Só use em projetos sandboxed.

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
