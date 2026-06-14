---
name: bmad-testarch-framework
description: "[alias bmad] Recomenda framework e comando de teste do projeto — produz spec em claude-didio-out/testarch/"
kind: command
targets: [claude, codex]
argument-hint: "<FXX>"
---

<!-- bmad-new: persona=QE phase=downstream -->

# /bmad-testarch-framework — recomendação de framework de teste

Você é o QE rodando `/bmad-testarch-framework $ARGUMENTS` no
`claude-didio-config`.

## Sua tarefa

1. **Extraia `<FXX>`** de `$ARGUMENTS`. Se ausente, abort:
   `usage: /bmad-testarch-framework <FXX> (e.g. /bmad-testarch-framework F27)`

2. **Resolva o diretório da feature**:
   ```bash
   FEATURE_DIR=$(ls -d tasks/features/<FXX>-* 2>/dev/null | head -n1)
   ```
   Se vazio, abort: `feature directory not found for <FXX>`.

3. **Calcule o slug.** Pegue o nome do diretório (`<FXX>-<slug>`), remova
   o prefixo `<FXX>-`. Esse é o `<slug>`.

4. **Calcule a data.** `YYYYMMDD` do dia (`Bash: date +%Y%m%d`).

5. **Leia o contexto.** `CLAUDE.md` (seção Stack/Build/Test/Run) e o
   `<FXX>-README.md` da feature, se existir.

6. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/testarch`.

7. **Escreva o arquivo.** Caminho:
   `claude-didio-out/testarch/<slug>-framework-<YYYYMMDD>.md`. Conteúdo:

   ```markdown
   # Test Framework — <FXX> <slug>

   _Gerado em <YYYY-MM-DD> por /bmad-testarch-framework._

   ## Stack detectada
   <stack relevante extraída de CLAUDE.md>

   ## Framework recomendado
   <framework de teste e justificativa>

   ## Comando de teste
   <comando(s) para rodar a suíte>

   ## Convenções
   <onde colocar testes novos, naming, fixtures>
   ```

8. **Reporte ao usuário.** Mensagem final em texto:

   ```
   ✅ Framework spec escrita: claude-didio-out/testarch/<slug>-framework-<YYYYMMDD>.md
   ```

## Regras (não-negociáveis)

- **NÃO** reimplemente o agente `tea` (F13). Este comando produz uma spec
  de framework, não substitui `/check-tests`.
- **NUNCA** dispare agentes externos via didio. Tudo roda no contexto deste
  prompt — sem run-wave, sem subprocess além de `Bash: date` / `Bash: ls` /
  `Bash: mkdir`.
- **NUNCA** escreva fora de `claude-didio-out/`.
- **NÃO** edite task files da feature.
