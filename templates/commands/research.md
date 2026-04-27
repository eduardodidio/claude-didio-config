---
description: Compila precedentes/blog posts/docs sobre um topic, com budget de WebSearch+WebFetch
argument-hint: "<topic>"
---

Você é o orquestrador de `/research` no `claude-didio-config`.

O usuário pediu pesquisa sobre: **$ARGUMENTS**

## Sua tarefa

1. **Leia o budget.** `Read didio.config.json` (ou
   `~/.claude-didio/didio.config.json` em downstream — preferir o do
   projeto). Extraia `research.web_search_budget` (default 5 se ausente)
   e `research.web_fetch_budget` (default 3 se ausente). Se o bloco
   `research` inteiro estiver ausente, use os defaults e siga.

2. **Calcule slug e data.** Igual a `/brainstorm` — kebab-case do
   $ARGUMENTS, `date +%Y%m%d`.

3. **Busque com budget rígido.** Mantenha contadores `n_search` e
   `n_fetch`. Pare de chamar `WebSearch` quando
   `n_search >= web_search_budget`; pare de chamar `WebFetch` quando
   `n_fetch >= web_fetch_budget`. **Conte cada chamada antes de fazer**
   (não depois).

   Estratégia sugerida (não obrigatória):
   - 1–2 `WebSearch` para queries amplas (precedentes / "X in
     production")
   - 1–2 `WebSearch` para queries técnicas (blog post,
     RFC, documentação)
   - 1–3 `WebFetch` em URLs mais promissoras dos resultados acima

4. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/research`.

5. **Escreva o arquivo.** Caminho:
   `claude-didio-out/research/<slug>-<YYYYMMDD>.md`. Conteúdo
   obrigatório (formato literal):

   ```markdown
   # Research — <topic original>

   _Gerado em <YYYY-MM-DD> por /research._

   ## Sources

   - [<título>](url) — <1 linha sobre por que é relevante>
   - [<título>](url) — ...
   - [<título>](url) — ...
   <... mínimo 3 entradas ...>

   ## Key findings

   - <achado 1>
   - <achado 2>
   ...

   ## Open questions

   - <pergunta que ficou em aberto 1>
   ...

   ---
   _Budget used: <N> WebSearch, <M> WebFetch_
   ```

   **Se WebSearch/WebFetch indisponível** (erro repetido / negação de
   permissão), escreva o arquivo mesmo assim: deixe `## Sources` com
   o literal `- _(WebSearch indisponível neste run)_`, popule `## Key
   findings` e `## Open questions` com o que o modelo já sabe sobre o
   topic, e registre o motivo em `## Open questions`. Rodapé:
   `_Budget used: 0 WebSearch, 0 WebFetch (web indisponível)_`.

6. **Reporte ao usuário.** Mensagem final:

   ```
   ✅ Research escrito: claude-didio-out/research/<slug>-<YYYYMMDD>.md
      Budget: <N>/<budget_search> WebSearch, <M>/<budget_fetch> WebFetch
   Próximo passo sugerido:
     • /product-brief  — para fundir com brainstorm existente
   ```

## Regras (não-negociáveis)

- **NUNCA** dispare agentes externos via didio (run-wave/subprocess).
- **NUNCA** ultrapasse `web_search_budget` ou `web_fetch_budget`.
- **SEMPRE** ≥3 entradas em `## Sources` (a menos que web inteiramente
  indisponível — ver passo 5).
- **SEMPRE** as 3 seções literais (`## Sources`, `## Key findings`,
  `## Open questions`) presentes — mesmo que vazias.
- **SEMPRE** rodapé `_Budget used: ...`.
