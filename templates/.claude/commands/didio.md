---
description: Menu interativo do framework claude-didio-config (criar feature, bug, revisar, dashboard, retro)
---

# /didio — Menu principal

Você é o menu interativo do `claude-didio-config`. Quando o usuário
invoca `/didio`, apresente as opções abaixo usando a ferramenta
**AskUserQuestion** (ou liste em texto se AskUserQuestion não estiver
disponível) e execute a ação escolhida.

## Opções do menu

1. **🆕 Criar nova feature**
   Pergunte: id da feature (F0X) e descrição curta.
   Execute: `/create-feature F0X <descrição>` ou o equivalente
   `didio spawn-agent architect F0X <brief>` com o workflow
   Architect → Waves → TechLead → QA.

2. **🐛 Corrigir um bug**
   Pergunte: descrição do bug + passos pra reproduzir.
   Execute: crie uma feature curta de 1 Wave, rode Developer,
   TechLead e QA.

3. **🔍 Revisar código desta branch (só TechLead)**
   Rode `didio spawn-agent techlead` sobre um brief que descreva os
   commits atuais da branch. Peça verdict BLOCKING / IMPORTANT / MINOR.

4. **📊 Status da execução atual**
   Leia `logs/agents/state.json` (se existir) e mostre:
   - Agentes rodando agora (status=running)
   - Última feature executada
   - Últimos 5 runs com status/duração/frase

5. **🖥️ Abrir dashboard — Didio Agents Dash**
   Execute `didio dashboard` via Bash tool. Avisa o usuário que o
   navegador vai abrir em localhost:7777.

6. **📚 Ver documentação**
   Liste o conteúdo de `docs/` — ADRs, PRDs, diagramas — e abra o
   INDEX se existir.

7. **🎓 Rodar retrospectiva manual**
   Pergunte: id da feature (F0X). Execute
   `didio spawn-agent qa F0X tasks/features/F0X*/F0X-README.md`
   com instrução extra "rode APENAS a cerimônia de retrospectiva".

8. **❓ Ajuda / prompts prontos**
   Mostre os prompts pré-configurados do README (criar feature,
   bug fix, revisão, plan mode, retro) pra o usuário copiar.

## Dica de higiene de contexto

Antes de qualquer opção que dispare novo trabalho (1, 2, 3, 7),
lembre o usuário:

> ⚠️ Se você acabou de terminar outra feature, rode `/clear`
> antes de começar a próxima. Contexto limpo = decisões melhores.

## Voltar ao menu

Pra voltar a este menu a qualquer momento, o usuário pode:
- Dentro do Claude Code: `/didio`
- No terminal: `didio menu` (ou só `didio` sem argumentos)
