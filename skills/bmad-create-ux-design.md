---
name: bmad-create-ux-design
description: "[BMAD] Produz spec de UX/design (telas, fluxos, estados) a partir do brief/PRD"
kind: command
targets: [claude, codex]
argument-hint: "<escopo ou caminho do brief/PRD>"
---

<!-- bmad-new: persona=PB+AIE phase=upstream -->

# /bmad-create-ux-design

Você é as personas **PB+AIE** no modo BMAD. Produza um spec de UX/design
para o escopo informado, cobrindo telas, fluxos e estados.

Escopo/input informado pelo usuário: **$ARGUMENTS**

## Sua tarefa

1. **Analise o input.** Se `$ARGUMENTS` apontar para um arquivo existente
   (ex: brief em `claude-didio-out/brainstorms/` ou PRD em
   `claude-didio-out/prd-drafts/`), leia-o para contexto. Se `$ARGUMENTS`
   for genérico demais (≤ 2 palavras e sem arquivo correspondente), pergunte
   ao usuário via `AskUserQuestion`:
   - "Qual fluxo principal o usuário precisa completar?"
   - "Existem telas/estados de erro críticos a cobrir?"
   Se `AskUserQuestion` indisponível, peça em texto e aguarde resposta.

2. **Calcule o slug.** A partir de `$ARGUMENTS` (sem aspas/path), lowercase,
   não-alphanumérico → `-`, colapse `-+`, trim, limite 60 chars.

3. **Calcule a data.** `YYYYMMDD` do dia (`Bash: date +%Y%m%d`).

4. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/ux-designs`.

5. **Escreva o arquivo.** Caminho:
   `claude-didio-out/ux-designs/<slug>-<YYYYMMDD>.md`. Conteúdo:

   ```markdown
   # UX Design — <escopo original>

   _Gerado em <YYYY-MM-DD> por /bmad-create-ux-design._

   ## Contexto
   <resumo do brief/PRD lido, ou das respostas à clarificação>

   ## Telas
   <lista das telas/views principais, com propósito de cada uma>

   ## Fluxos
   <fluxo(s) principal(is) passo a passo, do ponto de entrada ao objetivo>

   ## Estados
   <estados relevantes: loading, vazio, erro, sucesso>
   ```

6. **Reporte ao usuário.** Mensagem final em texto:

   ```
   ✅ UX design escrito: claude-didio-out/ux-designs/<slug>-<YYYYMMDD>.md
   Próximo passo sugerido:
     • /plan-feature  — para gerar a arquitetura e Waves a partir deste design
   ```

## Regras (não-negociáveis)

- **NUNCA** dispare agentes externos via didio. Tudo roda no contexto
  deste prompt — sem run-wave, sem subprocess (exceto `mkdir`/`date`).
- **NUNCA** escreva fora de `claude-didio-out/`.
