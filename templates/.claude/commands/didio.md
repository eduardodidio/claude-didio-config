---
description: Menu interativo do framework claude-didio-config (criar feature, bug, revisar, dashboard, retro)
---

# /didio — Menu principal

Você é o menu interativo do `claude-didio-config`. Quando o usuário
invoca `/didio`, apresente as opções abaixo usando a ferramenta
**AskUserQuestion** (ou liste em texto se AskUserQuestion não estiver
disponível) e execute a ação escolhida.

## Como apresentar o menu (2 níveis)

`AskUserQuestion` aceita no máximo 4 opções por pergunta — e este menu
tem 19 itens. Use **um menu em dois níveis**:

**Passo 1 — pergunte a categoria** (5 categorias; mostre 4 + "Other" para Greenfield):

1. **🚀 Trabalho** — criar feature, criar PRD, corrigir bug, revisar branch, planejar feature
   _(opções 1, 2, 3, 14, 16)_ — Trabalho tem 5 itens; use 4 na pergunta + "Other" para o 5º
2. **📊 Visibilidade** — status, dashboard, ver docs, listar features planejadas
   _(opções 4, 5, 6, 15)_
3. **🎓 Aprendizado & ajuda** — retrospectiva manual, prompts prontos
   _(opções 7, 8)_
4. **⚙️ Configurações** — turbo, economy, highlander, paralelismo, modelos
   _(opções 9, 10, 11, 12, 13)_
5. **🌱 Greenfield** — brainstorm, research, product brief _(opções 17, 18, 19)_
   _(apresente como "Other / Greenfield" na chamada do Passo 1 — o modelo mapeia para esta categoria)_

**Passo 2 — pergunte a ação dentro da categoria escolhida.** Apresente
apenas as opções daquela categoria (até 4 por vez). Para categorias
com 5 itens (**Trabalho**, **Configurações**), use 4 opções na pergunta
e ofereça o 5º item como “Other / mais opções” — ou faça duas chamadas.

Sempre que o usuário escolher “Other”, aceite texto livre e mapeie pra
opção mais próxima do menu numerado (1–19) abaixo.

## Opções do menu

1. **🆕 Criar nova feature**
   Pergunte: id da feature (F0X) e descrição curta.

   **OBRIGATÓRIO — execute as 4 fases sequencialmente, sem pular nenhuma:**

   **Fase 1 — Architect:** Analise o pedido, explore o código existente,
   produza um plano técnico com tarefas, testes e critérios de aceitação.
   Confirme o plano com o usuário antes de prosseguir.

   **Fase 1.5 — Readiness gate (audit pré-Wave):** Antes de chamar
   o Developer, rode `/check-readiness <FXX>`. O agent `readiness`
   produz `tasks/features/<FXX>-*/readiness-report.md` com veredito
   `READY` ou `BLOCKED`.

   Se BLOCKED: PARE o pipeline, mostre o path do report ao usuário,
   e oriente-o a corrigir o plano antes de re-rodar.

   Bypass de emergência: se `DIDIO_SKIP_READINESS=1` está no env,
   pule o gate (com aviso amarelo visível). **Nunca pule silenciosamente.**


   **Fase 1.6 — TEA gate (opcional):**

   <!-- F13:tea-gate coexists with F10:readiness — when F10 lands, run readiness FIRST and only proceed to TEA if verdict=READY -->

   Antes de iniciar a Fase 2, cheque o gate **TEA (Test Architect)**.
   TEA é opt-in via `didio.config.json:tea.enabled` (default: `false`).

   - Se `tea.enabled=false`: **pule silenciosamente** (caminho default,
     não notifique o usuário).
   - Se `DIDIO_SKIP_TEA=1`: pule e **avise** o usuário sobre o
     bypass.
   - Se F10 já merged (detecção: `agents/prompts/readiness.md`
     existe) e `tea.enabled=true`: rode `/check-readiness <FXX>`
     primeiro; se verdict `BLOCKED`, aborte; se `READY`, prossiga.
   - Caso contrário (`tea.enabled=true` e sem F10): rode
     `didio spawn-agent tea <FXX> tasks/features/<FXX>-*/<FXX>-README.md`.
     Aguarde finalizar. Se `<FXX>-test-plan.md` não foi criado, **avise
     mas não aborte** — TEA é advisory, não gating; QA ainda valida.

   **Fase 2 — Developer:** Implemente todas as tarefas do plano.
   Rode type-check e testes ao final.

   **Fase 3 — TechLead (Review):** Após implementar, revise TODO o código
   produzido seguindo `agents/prompts/review-tasks.md`. Classifique cada
   achado como BLOCKING / IMPORTANT / MINOR. Se houver BLOCKING, corrija
   antes de avançar. Apresente o resultado ao usuário.

   **Fase 4 — QA (Validação):** Após o review, valide seguindo
   `agents/prompts/qa-validate.md`. Rode testes (frontend e backend se
   aplicável). Reporte resultado final ao usuário.

   **A feature SÓ está concluída quando as 4 fases passarem.**
   Não pergunte ao usuário se deve rodar TechLead/QA — rode automaticamente.

2. **🐛 Corrigir um bug**
   Pergunte: descrição do bug + passos pra reproduzir.

   **OBRIGATÓRIO — execute 3 fases sequencialmente:**

   **Fase 1 — Developer:** Investigue a causa raiz, implemente a correção.
   Rode type-check e testes.

   **Fase 2 — TechLead (Review):** Revise o código da correção seguindo
   `agents/prompts/review-tasks.md`. Corrija achados BLOCKING.

   **Fase 3 — QA (Validação):** Valide seguindo `agents/prompts/qa-validate.md`.
   Rode testes. Reporte resultado final.

   **Retrospectiva:** Se o QA passar (verdict=PASSED), a cerimônia de
   retrospectiva roda automaticamente (já está no prompt do QA). Mesmo
   para bugs ad-hoc sem estrutura formal de tasks, o QA consegue extrair
   aprendizados de `git log` e do review.

3. **🔍 Revisar código desta branch (só TechLead)**
   Leia os commits recentes da branch (`git log --oneline -10` e `git diff main...HEAD`).
   Revise o código seguindo `agents/prompts/review-tasks.md`.
   Classifique cada achado como BLOCKING / IMPORTANT / MINOR.
   Apresente o resultado ao usuário.

   **Retrospectiva:** Ao final da revisão, como não há QA neste fluxo,
   o TechLead é responsável pela retrospectiva. Passe a instrução extra:
   `REVIEW_ONLY=true — você é o agente final neste fluxo. Execute a
   lightweight retrospective antes de terminar.`

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

14. **🗓️ Planejar feature (BMad, sem executar)**
    Pergunte: id da feature (F0X) e descrição.

    **Rode APENAS o Architect em modo PLAN_ONLY:**

    ```bash
    DIDIO_PLAN_ONLY=true didio spawn-agent architect <FXX> tasks/features/<FXX>-_tmp-brief.md
    ```

    O resultado são tasks em padrão BMad (User Story, Dev Notes, Testing)
    com `Status: planned`. **Não rode Developer, TechLead ou QA.** Ao final,
    informe o caminho dos arquivos e diga que o usuário pode rodar
    `/create-feature <FXX>` (ou opção 1) para executar depois.

    Equivale ao slash command `/plan-feature <FXX> <descrição>`.

    **Nota:** opção 14 não roda readiness gate — não dispara Waves.

15. **📋 Listar features planejadas**
    Varra `tasks/features/*/` procurando READMEs com `**Status:** planned`.
    Para cada feature encontrada, extraia ID, título e conte os arquivos
    `<FXX>-T*.md`. Apresente uma tabela: ID, #tasks, Título, Path.
    Se nenhuma feature planejada existir, sugira a opção 14.

16. **📝 Criar PRD antes de planejar (opt-in, interativo)**
    Pergunte: id da feature (F0X) e título curto. Execute
    `/elicit-prd <FXX> "<título>"` que faz 8 perguntas focadas e gera
    um draft em `claude-didio-out/prd-drafts/<FXX>-prd.md`.

    **Quando usar:** features novas em projetos downstream onde o brief
    ainda não está escrito. Após confirmação, copie o draft para
    `tasks/features/<FXX>-*/_brief.md` e siga com `/plan-feature` (opção
    14) ou `/create-feature` (opção 1).

    **Quando pular:** features triviais ou bugs — vá direto pra opção 1
    ou 2.

9. **⚡ Turbo Mode** (toggle)
   Ativa paralelismo maximo (ignora max_parallel). Combinado com
   Highlander, aciona Auto Mode do Claude Code.
   Toggle: `didio_write_config turbo true/false`

10. **💰 Economy Mode** (toggle)
    Troca modelos para versoes mais baratas:
    Architect = Sonnet, Developer/TechLead/QA = Haiku.
    Toggle: `didio_write_config economy true/false`

11. **🔀 Max paralelismo**
    Configura quantos agentes rodam simultaneamente por Wave.
    Recomendacoes: Opus 3-4, Sonnet 5-8, Haiku 8-12. Use 0 para ilimitado.

12. **🤖 Configurar modelos**
    Mostra e permite alterar o modelo de cada agente.
    Presets: Padrao, Economy, Tudo Opus, Tudo Sonnet.

13. **🛡️ Highlander Mode** (toggle) — _equivalente a Auto Mode on_
    Ativa o Auto Mode nativo do Claude Code via
    `permissions.defaultMode: "auto"` com allow-list liberal como
    fallback. Waves rodam sem interrupcao.
    Usar apenas em projetos sandbox sem segredos.


17. **🧠 Brainstorm — explorar 3–5 direções (greenfield, opt-in)**
    Pergunte: topic para brainstorm.

    Execute o slash command `/brainstorm "<topic>"`. Resultado:
    `claude-didio-out/brainstorms/<slug>-YYYYMMDD.md` com 3–5
    direções estruturadas (trade-offs explícitos).

    **Quando usar:** decisões greenfield — nova feature, nova lib,
    nova arquitetura. **Pular** para evolução de features existentes
    (vá para opção 1 ou 14).

    Equivale ao slash command `/brainstorm <topic>`.

18. **🔎 Research — compilar precedentes/blog posts (greenfield, opt-in)**
    Pergunte: topic para research.

    Execute o slash command `/research "<topic>"`. Resultado:
    `claude-didio-out/research/<slug>-YYYYMMDD.md` com precedentes,
    referências e análise comparativa.

    **Quando usar:** decisões greenfield onde precedentes externos
    importam. **Pular** para features com requisitos já conhecidos.

    Equivale ao slash command `/research <topic>`.

19. **🧾 Product brief — fundir brainstorm + research em brief (greenfield, opt-in)**
    Pergunte: id da feature (F0X) e título curto.

    Execute o slash command `/product-brief "<FXX>" "<título>"`.
    Funde os outputs de brainstorm + research num brief estruturado em
    `claude-didio-out/prd-drafts/<FXX>-brief.md`. Após confirmação,
    copie para `tasks/features/<FXX>-*/_brief.md` e siga com opção 14
    ou 1.

    **Quando usar:** após rodar opções 17 e 18, para consolidar antes
    de planejar. **Pular** para features com brief já definido.

    Equivale ao slash command `/product-brief <FXX> <título>`.

## Dica de higiene de contexto

Antes de qualquer opção que dispare novo trabalho (1, 2, 3, 7),
lembre o usuário:

> ⚠️ Se você acabou de terminar outra feature, rode `/clear`
> antes de começar a próxima. Contexto limpo = decisões melhores.

> 🛡️ Antes de rodar Waves de uma feature nova, o pipeline (opção 1)
> agora chama `/check-readiness` automaticamente. Para pular em
> emergência: `DIDIO_SKIP_READINESS=1`.

## Voltar ao menu

Pra voltar a este menu a qualquer momento, o usuário pode:
- Dentro do Claude Code: `/didio`
- No terminal: `didio menu` (ou só `didio` sem argumentos)
