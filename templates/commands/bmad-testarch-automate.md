---
description: "[alias bmad] (opt) Esboça automação de testes — produz spec em claude-didio-out/testarch/"
argument-hint: "<FXX>"
---

<!-- bmad-new: persona=QE phase=downstream -->

# /bmad-testarch-automate (opcional) — esboço de automação de testes

> **Opcional:** este comando não é obrigatório no fluxo BMAD downstream.
> Use apenas quando a feature justificar automação adicional além da
> suíte unitária/integration padrão (ex: E2E, smoke scripts).

Você é o QE rodando `/bmad-testarch-automate $ARGUMENTS` no
`claude-didio-config`.

## Sua tarefa

1. **Extraia `<FXX>`** de `$ARGUMENTS`. Se ausente, abort:
   `usage: /bmad-testarch-automate <FXX> (e.g. /bmad-testarch-automate F27)`

2. **Resolva o diretório da feature**:
   ```bash
   FEATURE_DIR=$(ls -d tasks/features/<FXX>-* 2>/dev/null | head -n1)
   ```
   Se vazio, abort: `feature directory not found for <FXX>`.

3. **Calcule o slug.** Pegue o nome do diretório (`<FXX>-<slug>`), remova
   o prefixo `<FXX>-`. Esse é o `<slug>`.

4. **Calcule a data.** `YYYYMMDD` do dia (`Bash: date +%Y%m%d`).

5. **Leia o contexto.** `<FXX>-README.md` e `<FXX>-test-plan.md` (se
   existir) para entender o escopo já coberto pela suíte padrão.

6. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/testarch`.

7. **Escreva o arquivo.** Caminho:
   `claude-didio-out/testarch/<slug>-automate-<YYYYMMDD>.md`. Conteúdo:

   ```markdown
   # Test Automation (opt) — <FXX> <slug>

   _Gerado em <YYYY-MM-DD> por /bmad-testarch-automate._

   ## Escopo já coberto
   <o que a suíte padrão já cobre, do test-plan>

   ## Gaps de automação
   <o que vale automatizar adicionalmente: E2E, smoke, perf>

   ## Esboço de scripts
   <esboço de comandos/scripts propostos>
   ```

8. **Reporte ao usuário.** Mensagem final em texto:

   ```
   ✅ Automation spec (opt) escrita: claude-didio-out/testarch/<slug>-automate-<YYYYMMDD>.md
   ```

## Regras (não-negociáveis)

- **NÃO** reimplemente o agente `tea` (F13). Este comando produz um
  esboço de automação, não substitui `/check-tests`.
- **NUNCA** dispare agentes externos via didio. Tudo roda no contexto deste
  prompt — sem run-wave, sem subprocess além de `Bash: date` / `Bash: ls` /
  `Bash: mkdir`.
- **NUNCA** escreva fora de `claude-didio-out/`.
- **NÃO** edite task files da feature.
