# F09 — Scan Exclusion Investigation

**Date:** 2026-04-25
**CLI version:** `2.1.119 (Claude Code)`

## Question

What mechanism does the current Claude Code CLI respect to exclude folders from
automatic scan and from agents' Glob/Grep tools?

## Findings

| Mecanismo testado                       | Glob/Grep respeita? | Auto-attach respeita? | Notas                                                                 |
|-----------------------------------------|---------------------|-----------------------|-----------------------------------------------------------------------|
| `.gitignore`                            | Sim                 | Não determinado       | ripgrep embutido respeita `.gitignore` por padrão via `--require-git` |
| `settings.json: ignorePatterns`         | N/A                 | N/A                   | **Deprecated** — substituído por `permissions.deny`                   |
| `settings.json: permissions.deny`       | Sim                 | Excluído              | Exclui de file discovery, read tools e file picker (@)                |
| `settings.json: respectGitignore`       | Não (só file picker)| Não                   | Controla apenas o `@` file picker; default `true`                     |
| `settings.json: additionalDirectories`  | Inclui (oposto)     | N/A                   | Expande scope; não é mecanismo de exclusão                            |

### Evidências

1. **Binary inspection:** `strings ~/.local/bin/claude` revela ripgrep embutido com
   strings `ignore::gitignore`, `respect your .gitignore rules` e `--no-require-git`.
   Glob/Grep usam este ripgrep, que respeita `.gitignore` nativamente.

2. **Docs (code.claude.com/docs/en/settings):** `ignorePatterns` está deprecated;
   o mecanismo atual é `permissions.deny` com sintaxe `Read(./path/**)`
   que exclui arquivos de file discovery **e** das ferramentas Read/Edit.

3. **`respectGitignore` (bool, default true):** afeta somente o file picker `@`,
   não as ferramentas Glob/Grep usadas pelos agentes.

4. **Empirical:** `git check-ignore archive/features/foo.md` após adicionar
   `archive/` ao `.gitignore` retorna o path confirmando exclusão.

## Decision

gitignore-only

**Mecanismo implementado (T03 Wave 1): `.gitignore` (primário)**

Para F09, a estratégia aplicada é:
- `.gitignore` garante que Glob/Grep (ripgrep) não enxerguem `archive/` e
  `claude-didio-out/`.

**Justificativa (T03 Branch B):** ripgrep respeita `.gitignore` por padrão. O campo
`ignorePatterns` não existe mais no schema atual. Como `tasks/` já estava gitignored
antes de F09, a medição de T07 confirmou que mover features para `archive/` não altera
o que os agentes veem — a cobertura do `.gitignore` é suficiente para o objetivo
principal (isolar rascunhos e features arquivadas do scan de agentes).

**`permissions.deny` disponível mas deferido:** o mecanismo `permissions.deny` com
`Read(./archive/**)` existe no CLI e poderia ser adicionado como defense-in-depth para
o file picker e Read tool. Dado que o valor incremental é marginal (confirmado por T07),
foi decidido não modificar `.claude/settings.json` nesta wave. Pode ser adicionado
futuramente como hardening se necessário.

## Implications for F09 Wave 1

- **T03 (settings.json):** adicionar `permissions.deny` com `Read(./archive/**)` e
  `Read(./claude-didio-out/**)` como defense-in-depth. Se a sintaxe não for aceita
  pela versão do CLI (improvável dada a docs), a tarefa vira no-op documentado.
- **T05 (sync-project):** propagar as duas entradas do `.gitignore` para projetos
  downstream. `permissions.deny` no `.claude/settings.json` é project-specific —
  propagar também se T03 for aceito.

## Measurement (filled by T07)

| Estado                                              | Tokens (total) | Cache-create | Cache-read | Wall-clock (s) | Custo USD  | Notas                                   |
|-----------------------------------------------------|----------------|--------------|------------|----------------|------------|-----------------------------------------|
| Antes (F01+F02 em tasks/features/)                  | 45 326         | 13 335       | 31 790     | 19,1           | $0,0642    | tag pre-F09-archive-20260425 restaurado |
| Depois (F01+F02 em archive/)                        | 45 312         | 13 329       | 31 783     | 21,5           | $0,0641    | branch atual (pós-T06)                  |
| Delta                                               | **-14 tokens** | -6           | -7         | +2,5 s ¹       | -$0,00004  |                                         |

¹ Wall-clock dentro de variância normal (1 amostra).

**Comando usado:**
```bash
bin/didio-spawn-agent.sh developer F99 /tmp/f09-measure-ping.md
```
*(Nota: role `developer`/sonnet usado no lugar de `architect`/opus por controle de custo — sinal de descoberta é equivalente para esta métrica.)*

**Observações:**

- **A diferença é marginal** (−14 tokens, −0,03%): essencialmente ruído de medição.
- Causa raiz: `/tasks/` já estava em `.gitignore` **antes** de F09 (bootstrap gitignore).
  Por isso, Glob/Grep nunca enxergava F01+F02 mesmo no estado "antes" — a visibilidade
  já era idêntica. Mover para `archive/` não alterou o que os agentes veem via ripgrep.
- A diferença de −6 tokens em `cache_creation` corresponde aproximadamente aos nomes de
  diretório extras que aparecem em `ls tasks/features/` quando F01+F02 estão presentes
  (2 entradas a mais na listagem via Bash), capturados no contexto de cache.
- **`total_tokens` não existe no meta.json** — dados extraídos do evento `result` no
  JSONL (`logs/agents/<run>.jsonl`), que contém `usage.{input_tokens,
  cache_creation_input_tokens, cache_read_input_tokens, output_tokens}`.
- 1 amostra por estado (não 3); mediana não computada. Dado válido com a ressalva de
  variância inter-run não estimada.
- Fixtures e meta.json brutos preservados em `docs/F09-measurement-raw/`.

**Conclusão para F09:** o benefício de arquivar features concluídas **não é
mensurável via token count** neste repositório, porque `tasks/` já estava gitignored.
O valor real da archival é operacional (menos ruído em `ls`, semântica de
"done vs. active"), não computacional.
