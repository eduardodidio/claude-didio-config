---
description: "[alias bmad] Descreve/valida config de CI de teste — produz spec em claude-didio-out/testarch/"
argument-hint: "<FXX>"
---

<!-- bmad-new: persona=QE phase=downstream -->

# /bmad-testarch-ci — config de CI de teste

Você é o QE rodando `/bmad-testarch-ci $ARGUMENTS` no `claude-didio-config`.

## Sua tarefa

1. **Extraia `<FXX>`** de `$ARGUMENTS`. Se ausente, abort:
   `usage: /bmad-testarch-ci <FXX> (e.g. /bmad-testarch-ci F27)`

2. **Resolva o diretório da feature**:
   ```bash
   FEATURE_DIR=$(ls -d tasks/features/<FXX>-* 2>/dev/null | head -n1)
   ```
   Se vazio, abort: `feature directory not found for <FXX>`.

3. **Calcule o slug.** Pegue o nome do diretório (`<FXX>-<slug>`), remova
   o prefixo `<FXX>-`. Esse é o `<slug>`.

4. **Calcule a data.** `YYYYMMDD` do dia (`Bash: date +%Y%m%d`).

5. **Leia o contexto.** Procure por configs de CI existentes (ex:
   `.github/workflows/*.yml`) e o comando de teste em `CLAUDE.md`.

6. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/testarch`.

7. **Escreva o arquivo.** Caminho:
   `claude-didio-out/testarch/<slug>-ci-<YYYYMMDD>.md`. Conteúdo:

   ```markdown
   # Test CI — <FXX> <slug>

   _Gerado em <YYYY-MM-DD> por /bmad-testarch-ci._

   ## CI atual
   <workflows existentes que rodam testes, ou "nenhum encontrado">

   ## Gaps
   <o que falta para a suíte rodar em CI: triggers, steps, caching>

   ## Config recomendada
   <trecho de workflow/job recomendado>
   ```

8. **Reporte ao usuário.** Mensagem final em texto:

   ```
   ✅ CI spec escrita: claude-didio-out/testarch/<slug>-ci-<YYYYMMDD>.md
   ```

## Regras (não-negociáveis)

- **NÃO** reimplemente o agente `tea` (F13). Este comando produz uma spec
  de CI, não substitui `/check-tests`.
- **NUNCA** dispare agentes externos via didio. Tudo roda no contexto deste
  prompt — sem run-wave, sem subprocess além de `Bash: date` / `Bash: ls` /
  `Bash: mkdir`.
- **NUNCA** escreva fora de `claude-didio-out/`.
- **NÃO** edite workflows de CI existentes — apenas descreva/recomende.
- **NÃO** edite task files da feature.
