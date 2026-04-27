---
description: Gera 3–5 direções de design com trade-offs (input para /elicit-prd ou /plan-feature)
argument-hint: "<topic>"
---

Você é o orquestrador de `/brainstorm` no `claude-didio-config`.

O usuário pediu brainstorm sobre: **$ARGUMENTS**

## Sua tarefa

1. **Analise o topic.** Se for genérico demais (≤ 2 palavras OU sem
   contexto explícito de sistema), pergunte ao usuário via
   `AskUserQuestion`:
   - "Qual sistema/feature isso resolve?"
   - "Qual restrição é mais importante: tempo / qualidade / escopo?"
   Se `AskUserQuestion` indisponível, peça em texto e aguarde resposta.
   Se topic já for específico, pule este passo.

2. **Gere 3 a 5 direções.** Cada uma DEVE ter exatamente este formato
   literal:

   ```
   ### Direção <N> — <título curto>
   **Quem ganha / Quem perde:** <quem ganha>; <quem perde>
   **Esforço estimado:** <S | M | L | XL>
   **Risco principal:** <risco>
   **Pré-condição:** <o que precisa estar verdadeiro>
   ```

3. **Calcule o slug.** Pegue $ARGUMENTS (sem aspas), faça lowercase,
   troque não-alphanumérico por `-`, colapse `-+` em `-`, trim.
   Limite a 60 chars.

4. **Calcule a data.** `YYYYMMDD` do dia (use `Bash: date +%Y%m%d`).

5. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/brainstorms`.

6. **Escreva o arquivo.** Caminho:
   `claude-didio-out/brainstorms/<slug>-<YYYYMMDD>.md`. Conteúdo:

   ```markdown
   # Brainstorm — <topic original>

   _Gerado em <YYYY-MM-DD> por /brainstorm._

   ## Contexto
   <1 parágrafo: sistema/restrições aprendidos no passo 1, ou "topic já
    específico, sem clarificação adicional">

   ## Direções

   ### Direção 1 — ...
   ...

   ### Direção 5 — ...
   ...
   ```

7. **Reporte ao usuário.** Mensagem final em texto:

   ```
   ✅ Brainstorm escrito: claude-didio-out/brainstorms/<slug>-<YYYYMMDD>.md
   Próximo passo sugerido:
     • /research "<topic>"  — para validar com precedentes/blog posts
     • /product-brief       — para fundir com research existente
   ```

## Regras (não-negociáveis)

- **NUNCA** dispare agentes externos via didio. Tudo roda no contexto
  deste prompt — sem run-wave, sem subprocess.
- **NUNCA** escreva fora de `claude-didio-out/` ou crie `.gitkeep`.
- **SEMPRE** entre 3 e 5 direções (nem 2, nem 6+).
- **SEMPRE** as 5 facetas literais por direção (ordenadas como acima).
