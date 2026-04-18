# ADR — F06: destino de `memory/agent-learnings/*.md` após a integração com second-brain

**Status:** Accepted
**Date:** 2026-04-18
**Context feature:** F06 (integração second-brain MCP)

## Context

A F06 introduziu o fluxo via `mcp__second-brain__memory_search` pra substituir
a leitura direta dos arquivos `memory/agent-learnings/<role>.md` no início
de cada spawn. Com essa mudança, o conteúdo dos arquivos locais e o índice
do second-brain passam a representar (parcialmente) a mesma informação:

- **Arquivos locais**: fonte histórica das retrospectivas; ainda usados como
  fallback pelos prompts quando `second_brain.enabled=false` ou MCP
  indisponível.
- **Second-brain**: índice cross-project, buscável por keyword, alimentado
  pela migração one-shot (`bin/didio-migrate-learnings.sh`) e pela
  cerimônia de retrospectiva do QA (passo 3b do `templates/agents/prompts/qa.md`).

A pergunta desta ADR é: o que fazer com `memory/agent-learnings/*.md` daqui
pra frente?

## Alternativas consideradas

### (A) Deletar os arquivos locais

Remover `memory/agent-learnings/` depois que a migração confirmar
ingestão completa no second-brain.

- Prós: single source of truth; zero risco de divergência.
- Contras:
  - Quebra o fallback quando MCP offline (os prompts dependem deste caminho
    em `fallback_to_local=true`, que é o default).
  - Requer que **todos** os downstream projects do `didio-sync` já tenham
    MCP wired up — acoplamento forte.
  - Perde o histórico inspecionável via `git log memory/agent-learnings/`.

### (B) Mover pra `docs/archive/`

Tirar do caminho ativo mas preservar como snapshot histórico.

- Prós: preserva histórico, sinaliza "não é mais fonte ativa".
- Contras:
  - Requer mudar os caminhos nos 4 prompt templates (fallback branch
    aponta pra `memory/agent-learnings/<role>.md`).
  - O sync downstream (`didio-sync-project.sh`) copia `memory/agent-learnings/`;
    mudar pra `docs/archive/` exige ajustar a lista de paths sincronizados.
  - Muda contrato sem ganho operacional — "archive" sugere leitura zero,
    mas o arquivo ainda é read-path ativo durante fallback.

### (C) Manter como fallback read-only (RECOMENDADO)

Arquivos continuam onde estão. A partir da F06:

- Cerimônia de retro (QA passo 3) continua fazendo **append** local
  (unchanged).
- QA passo 3b **também** grava via `memory_add` no second-brain.
- Os dois caminhos ficam em sync por construção (mesma origem, ambos
  escritos pelo mesmo agente na mesma iteração).
- Nenhum dos prompts precisa de alteração de path.
- Downstream projects sincronizam o mesmo `memory/agent-learnings/` por
  mais tempo; quando todos estiverem com MCP, uma ADR futura (fora do
  escopo da F06) pode reconsiderar.

- Prós: zero quebra; fallback mantido; dual-write automático.
- Contras:
  - Custo extra de ~1 call `memory_add` por lesson por feature (aceitável:
    3–5 adds por retro, ≤ 10s total).
  - Risco de divergência se algum agente apender local e pular o `memory_add`
    ou vice-versa. Mitigação: teste do prompt qa.md garante presença do
    passo 3b.

## Decision

**Escolhida: (C) manter como fallback read-only com dual-write pela retro.**

Motivos:
1. Zero risco operacional — o fallback é um contrato explícito da F06
   (`fallback_to_local=true` default).
2. Dual-write na retro não custa trabalho extra porque a informação já
   está na mão do QA naquele momento.
3. Deixa a porta aberta pra decisão futura quando todos os downstream
   projects tiverem MCP integrado.

## Consequences

- `memory/agent-learnings/*.md` permanecem no repo e são sincronizados
  pelo `didio-sync-project.sh` como antes.
- Toda retrospectiva gera 2 escritas (1 local + 1 MCP) — ADR futura pode
  optar por consolidar quando a aderência ao second-brain for universal.
- Monitoramento sugerido: se `memory_search` retornar consistentemente
  dados mais antigos que o append local (indicador de drift), abrir
  follow-up pra reforçar o passo 3b.

## Related

- `templates/agents/prompts/qa.md` — passo 3 (append local) + passo 3b
  (mirror pro second-brain)
- `bin/didio-migrate-learnings.sh` — migração one-shot (histórico completo)
- `didio.config.json` → `second_brain.fallback_to_local` (default `true`)
