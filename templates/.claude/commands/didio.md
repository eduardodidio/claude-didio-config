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

   **OBRIGATÓRIO — execute as 4 fases sequencialmente, sem pular nenhuma:**

   **Fase 1 — Architect:** Analise o pedido, explore o código existente,
   produza um plano técnico com tarefas, testes e critérios de aceitação.
   Confirme o plano com o usuário antes de prosseguir.

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

15. **📋 Listar features planejadas**
    Varra `tasks/features/*/` procurando READMEs com `**Status:** planned`.
    Para cada feature encontrada, extraia ID, título e conte os arquivos
    `<FXX>-T*.md`. Apresente uma tabela: ID, #tasks, Título, Path.
    Se nenhuma feature planejada existir, sugira a opção 14.

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

## Dica de higiene de contexto

Antes de qualquer opção que dispare novo trabalho (1, 2, 3, 7),
lembre o usuário:

> ⚠️ Se você acabou de terminar outra feature, rode `/clear`
> antes de começar a próxima. Contexto limpo = decisões melhores.

## Voltar ao menu

Pra voltar a este menu a qualquer momento, o usuário pode:
- Dentro do Claude Code: `/didio`
- No terminal: `didio menu` (ou só `didio` sem argumentos)
