# Economy mode — quando usar

## TL;DR

- **Standard** (Sonnet com effort=medium): default. Use sempre que a feature é
  produção, refactor, ou tem audit-trail relevante.
- **Economy** (Haiku, sem effort): tarefas auxiliares de baixo risco e baixo
  escopo. Drafts, scripts utilitários, exploração.

## O que muda

| Aspecto                       | Standard               | Economy             |
|-------------------------------|------------------------|---------------------|
| Architect                     | Opus                   | Sonnet              |
| Developer/TechLead/QA         | Sonnet (effort=medium) | Haiku (sem effort)  |
| Custo (~)                     | 1×                     | ~0.1× (estimado)    |
| Qualidade percebida           | Alta                   | Média; revisar mais |
| Latência                      | Maior                  | Menor               |

## Quando ATIVAR (`economy: true`)

- PoC isolado, sem merge para main.
- Geração de fixtures/seeds que serão revisadas e re-rodadas.
- Sweep de cleanup de TODOs triviais.
- Bug-fix tipo typo/comment que não toca lógica.

## Quando MANTER OFF

- Features que vão para produção sem revisão humana posterior.
- Mudanças de schema/migration.
- Hooks de segurança (PreToolUse, PostToolUse).
- Refactors que tocam contratos.

## Como ativar

```bash
# direto no config:
python3 -c "import json; c=json.load(open('../didio.config.json')); c['economy']=True; json.dump(c, open('../didio.config.json','w'), indent=2)"
```

(Um helper `./bin/didio config set economy true` poderá ser adicionado no futuro.)

## Reverter

Setar `economy: false` em `../didio.config.json`. Não há side-effect persistente
— a próxima spawn já usa o tier definido.

## Referências

- `../didio.config.json` campos `models` e `models_economy`
- `../bin/didio-config-lib.sh` função `didio_model_for_role`
