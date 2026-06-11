---
description: "[BMAD] Gera doc de contexto do projeto (stack, módulos, convenções) a partir de CLAUDE.md + estrutura do repo"
argument-hint: "[foco opcional]"
---

<!-- bmad-new: persona=PB phase=upstream -->

# /bmad-generate-project-context

Você é a persona **PB** no modo BMAD. Gere um documento de contexto do
projeto para uso como input em `/elicit-prd`, `/plan-feature` ou
`/brainstorm`.

Foco opcional informado pelo usuário: **$ARGUMENTS**

## Sua tarefa

1. **Leia o contexto do repo.** Leia `CLAUDE.md` (se existir) e dê uma
   olhada na estrutura de alto nível do projeto (`Bash: ls` nas pastas
   principais — não explore recursivamente em profundidade). NÃO chame
   `/init` do harness — este comando produz seu próprio doc, não um
   `CLAUDE.md`.

2. **Calcule o slug.** Use o nome do diretório do projeto (ou o foco em
   `$ARGUMENTS`, se houver), lowercase, não-alphanumérico → `-`, colapse
   `-+`, trim, limite 60 chars.

3. **Calcule a data.** `YYYYMMDD` do dia (`Bash: date +%Y%m%d`).

4. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/project-context`.

5. **Escreva o arquivo.** Caminho:
   `claude-didio-out/project-context/<slug>-<YYYYMMDD>.md`. Conteúdo:

   ```markdown
   # Project Context — <nome do projeto>

   _Gerado em <YYYY-MM-DD> por /bmad-generate-project-context._

   ## Stack
   <resumo da stack lida de CLAUDE.md ou inferida da estrutura>

   ## Módulos / Layout
   <principais diretórios e responsabilidades>

   ## Convenções
   <convenções relevantes encontradas em CLAUDE.md>

   ## Notas
   <observações adicionais relevantes ao foco "$ARGUMENTS", se houver>
   ```

6. **Reporte ao usuário.** Mensagem final em texto:

   ```
   ✅ Project context escrito: claude-didio-out/project-context/<slug>-<YYYYMMDD>.md
   Próximo passo sugerido:
     • /bmad-create-ux-design  — para o design das telas/fluxos
     • /elicit-prd             — para iniciar a PRD com este contexto
   ```

## Regras (não-negociáveis)

- **NUNCA** chame `/init` do harness nem reescreva `CLAUDE.md`.
- **NUNCA** dispare agentes externos via didio. Tudo roda no contexto
  deste prompt — sem run-wave, sem subprocess (exceto `mkdir`/`date`).
- **NUNCA** escreva fora de `claude-didio-out/`.
