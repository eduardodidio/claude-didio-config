---
description: Re-rodar TEA (Test Architect) numa feature existente para regenerar `<FXX>-test-plan.md`
argument-hint: <FXX>
---

You are orchestrating the **TEA gate** for feature **$ARGUMENTS** in
project **{{PROJECT_NAME}}**.

## Pipeline

1. Extract `<FXX>` from `$ARGUMENTS`. If missing, abort with:
   `usage: /check-tests <FXX> (e.g. /check-tests F13)`
2. Resolve the feature directory:
   ```bash
   FEATURE_DIR=$(ls -d tasks/features/<FXX>-* 2>/dev/null | head -n1)
   ```
   If empty, abort: `feature directory not found for <FXX>`.
3. Read `didio.config.json:tea.enabled`. If `false`, print:
   `[check-tests] tea.enabled=false in config — running anyway by manual invocation`
   and continue. (Manual invocation overrides the global flag because
   the user explicitly asked for it.)
4. Check `DIDIO_SKIP_TEA`. If `1`, abort:
   `[check-tests] DIDIO_SKIP_TEA=1 — bypass active, refusing to run`
5. If `<FXX>-test-plan.md` already exists, back it up:
   ```bash
   cp "$FEATURE_DIR/<FXX>-test-plan.md" "claude-didio-out/tea/<FXX>-test-plan.$(date +%s).bak"
   ```
6. Spawn TEA:
   ```bash
   didio spawn-agent tea <FXX> "$FEATURE_DIR/<FXX>-README.md"
   ```
7. After it finishes, verify `<FXX>-test-plan.md` exists in
   `$FEATURE_DIR`. Verify it has all 7 sections per
   `docs/F13-test-plan-spec.md` (header, Fixtures, Harnesses, Perf
   budgets, Mocks, Test scenarios resumo, Anotações).
8. Report verdict:
   - `WRITTEN` if first time.
   - `UPDATED` if re-run (backup exists).
   - `FAILED` if spawn exit code ≠ 0 or the file is missing.

## Bypass de emergência

Para pular a TEA gate em emergência, defina `DIDIO_SKIP_TEA=1` no env
antes de rodar `/create-feature` ou `/didio` opção 1. O comando
`/check-tests` se recusa a rodar com esse bypass ativo (não faz sentido
manual invocation com bypass — desative `DIDIO_SKIP_TEA` primeiro).

**Nunca pule silenciosamente.** O orquestrador deve imprimir um aviso
amarelo visível quando o bypass está ativo.

## Ligando TEA

Por padrão, `tea.enabled` é `false` em `didio.config.json`. Para ativar
TEA globalmente (rodando automaticamente em todas as Waves):

```json
{
  "tea": { "enabled": true }
}
```

**Override por feature:** atualmente não suportado — flag é global.
Se precisar desligar para uma feature específica, use
`DIDIO_SKIP_TEA=1 /create-feature ...`.
