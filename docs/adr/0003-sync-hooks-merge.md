# ADR-0003: Merge de `hooks` em `didio-sync-project.sh` com dedupe por `command`

**Status:** accepted
**Date:** 2026-04-20
**Deciders:** @eduardodidio

## Context

F06 propagou o bloco `hooks` do hub `didio-second-brain-claude` para 5 projetos
downstream manualmente, porque `didio-sync-project.sh` só mesclava
`permissions.allow`. Para projetos novos sincronizados após F06, precisamos que
o script faça esse merge automaticamente.

O contrato existente (merge de `permissions.allow`) usa `python3` para ler os
dois `settings.json`, calcular a união e escrever o resultado. A extensão para
`hooks` reutiliza a mesma abordagem.

A questão de design é: **como mesclar `hooks.<event>[].hooks[]` quando o destino
já possui hooks** (custom ou previamente sincronizados)?

Três invariantes devem ser preservados:

1. **Idempotência** — rodar `didio sync-project` duas vezes deve produzir
   `NO_CHANGE` na segunda execução.
2. **Não-destrutividade** — hooks custom já presentes no destino não podem ser
   removidos ou sobrescritos.
3. **Blast radius mínimo** — uma falha de sincronização (hub movido, path
   inválido) não deve corromper o `settings.json` do destino.

Feedback relevante: `feedback_discord_hooks_env.md` no hub documenta que hooks
disparam em silêncio quando as variáveis `DISCORD_*` não estão carregadas —
indicando que o campo `command` (string completa) é o identificador estável de
um hook em runtime, mais confiável do que a combinação `(matcher, command)`.

## Decision

Mesclar `hooks.<event>[].hooks[]` do template no destino com **dedupe por
`command`** (string completa do campo `command`).

**Algoritmo** (implementado em `bin/didio-sync-project.sh`, seção 5, no
mesmo heredoc `python3` que trata `permissions.allow`):

```python
src_hooks = src.get("hooks", {})
dst_hooks = dst.get("hooks", {})
hooks_added = 0

for event, src_matchers in src_hooks.items():
    dst_matchers = dst_hooks.setdefault(event, [])
    existing_cmds = {
        h.get("command")
        for m in dst_matchers
        for h in m.get("hooks", [])
        if h.get("command")
    }
    for src_matcher in src_matchers:
        matcher_val = src_matcher.get("matcher", "*")
        target = next(
            (m for m in dst_matchers if m.get("matcher") == matcher_val), None
        )
        for hook in src_matcher.get("hooks", []):
            cmd = hook.get("command")
            if not cmd or cmd in existing_cmds:
                continue
            if target is None:
                target = {"matcher": matcher_val, "hooks": []}
                dst_matchers.append(target)
            target.setdefault("hooks", []).append(hook)
            existing_cmds.add(cmd)
            hooks_added += 1
```

**Output contract** (retrocompatível com consumidores existentes):

- `NO_CHANGE` — nenhuma permission nova **nem** nenhum hook novo.
- `MERGED:perms=<N>,hooks=<M>` — novo formato; bash parseia com regex
  `^MERGED:perms=([0-9]+),hooks=([0-9]+)$` e compõe log:
  `"<N> permissions + <M> hooks added"`.

## Consequences

- ✅ **Idempotente**: segunda execução encontra todos os `command` em
  `existing_cmds` → `hooks_added=0` → `NO_CHANGE`.
- ✅ **Não-destrutiva**: hooks custom no destino que não estão no template
  são preservados (o algoritmo nunca remove entradas do destino).
- ✅ **Blast radius mínimo**: se o hub for movido e o `command` com path
  absoluto ficar desatualizado, o hook antigo fica como lixo no destino até
  limpeza manual — aceitável; o `settings.json` não é corrompido.
- ⚠️ **Dois matchers distintos com mesmo `command`**: o segundo é descartado.
  Se alguém quiser disparar o mesmo script via dois matchers diferentes, essa
  intenção é silenciosamente perdida — tradeoff conhecido e documentado aqui.
- ⚠️ **Path absoluto em `command`**: mover o hub invalida o command sem aviso.
  Mitigação: `didio sync-project` deve ser rodado após mover o hub.

## Alternatives considered

- **Substituição total (`hooks` do template substitui o do destino)** — rejeitada.
  Destrói hooks custom do destino sem recuperação possível; viola invariante
  não-destrutivo.

- **Dedupe por `(matcher, command)`** — rejeitada. Permite que o mesmo script
  apareça em dois matchers distintos, gerando dupla notificação Discord para o
  mesmo evento. O campo `command` sozinho já identifica o handler; o `matcher`
  é um filtro de dispatch, não parte da identidade do hook.

- **Merge sem dedupe** — rejeitada. Segunda execução do sync duplica todos os
  hooks já presentes; idempotência quebrada; `settings.json` cresce sem limite.

- **Forçar `matcher: "*"` em todos os hooks do template** — rejeitada.
  Opinionated demais; impede que projetos downstream usem matchers específicos
  por ferramenta. O algoritmo atual preserva o `matcher` do template.

## Links

- F06-T11 (implementação da extensão do sync script): `tasks/features/F06-hooks-rollout-downstream/F06-T11.md` — commit: `<F06-T11 commit>` <!-- TODO: QA preenche após merge -->
- ADR-0002 (layout canônico e estratégias de merge): `docs/adr/0002-canonical-project-layout.md`
- Hub feedback sobre hooks e `.env`: `feedback_discord_hooks_env.md` (user-auto-memory do hub `didio-second-brain-claude`)
- Padrões de hooks: `patterns/hooks/` no hub (referência de exemplo; o contrato é sobre `command` string, não sobre paths de diretório)
