---
name: bmad-testarch-atdd
description: "[alias bmad] Gera testes de aceitação (ATDD) a partir dos AC, antes do dev — produz spec em claude-didio-out/testarch/"
kind: command
targets: [claude, codex]
argument-hint: "<FXX>"
---

<!-- bmad-new: persona=QE phase=downstream -->

# /bmad-testarch-atdd — testes de aceitação a partir dos AC

Você é o QE rodando `/bmad-testarch-atdd $ARGUMENTS` no `claude-didio-config`.

## Sua tarefa

1. **Extraia `<FXX>`** de `$ARGUMENTS`. Se ausente, abort:
   `usage: /bmad-testarch-atdd <FXX> (e.g. /bmad-testarch-atdd F27)`

2. **Resolva o diretório da feature**:
   ```bash
   FEATURE_DIR=$(ls -d tasks/features/<FXX>-* 2>/dev/null | head -n1)
   ```
   Se vazio, abort: `feature directory not found for <FXX>`.

3. **Calcule o slug.** Pegue o nome do diretório (`<FXX>-<slug>`), remova
   o prefixo `<FXX>-`. Esse é o `<slug>`.

4. **Calcule a data.** `YYYYMMDD` do dia (`Bash: date +%Y%m%d`).

5. **Leia os AC.** Para cada `<FXX>-TYY.md` em `$FEATURE_DIR`, extraia a
   seção `## Acceptance criteria`. Se houver `<FXX>-README.md`, leia-o
   para o objetivo geral da feature.

6. **Crie o diretório.** `Bash: mkdir -p claude-didio-out/testarch`.

7. **Escreva o arquivo.** Caminho:
   `claude-didio-out/testarch/<slug>-atdd-<YYYYMMDD>.md`. Conteúdo:

   ```markdown
   # ATDD — <FXX> <slug>

   _Gerado em <YYYY-MM-DD> por /bmad-testarch-atdd._

   ## Acceptance criteria cobertos
   <lista de AC por task, copiados das task files>

   ## Cenários ATDD
   Para cada AC, no formato Given/When/Then:

   ### AC<N> — <descrição curta>
   - **Given** <pré-condição>
   - **When** <ação>
   - **Then** <resultado esperado>
   ```

8. **Reporte ao usuário.** Mensagem final em texto:

   ```
   ✅ ATDD spec escrita: claude-didio-out/testarch/<slug>-atdd-<YYYYMMDD>.md
   ```

## Regras (não-negociáveis)

- **NÃO** reimplemente o agente `tea` (F13). Este comando produz cenários
  ATDD a partir dos AC, não substitui `/check-tests`.
- **NUNCA** dispare agentes externos via didio. Tudo roda no contexto deste
  prompt — sem run-wave, sem subprocess além de `Bash: date` / `Bash: ls` /
  `Bash: mkdir`.
- **NUNCA** escreva fora de `claude-didio-out/`.
- **NÃO** edite task files da feature.
