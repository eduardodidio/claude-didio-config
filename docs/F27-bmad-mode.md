# F27 — Modo BMAD (Greenfield + Brownfield)

## 1. Visão geral

O modo BMAD é uma camada **aditiva** sobre o pipeline didio existente
(Architect → Developer → TechLead → QA). Ele NÃO reescreve esse pipeline:

- `/bmad-*` são **aliases finos** que delegam a comandos didio já existentes
  (F09–F14), sem duplicar lógica.
- Os poucos **comandos novos** (`generate-project-context`,
  `create-ux-design`, `testarch-*`, `sprint-planning`, `correct-course`)
  cobrem apenas os primitives que faltam para Greenfield (GF) e Brownfield
  (BF).
- Um **selector `/bmad <greenfield|brownfield>`** encadeia upstream→downstream,
  pausando na fronteira de fase e reusando os gates existentes (Gandalf,
  readiness/F10, TEA/F13).
- Nenhum agente novo foi criado — as personas BMAD (PB/AIE/QE) mapeiam para
  os agentes didio atuais (`architect`, `developer`, `tea`, `qa`).

## 2. Os 5 workflows

A imagem `bmadRules.png` define 5 workflows, cada um com fase **UPSTREAM**
(descoberta→plano) e **DOWNSTREAM** (execução→retrospectiva). Esta feature
implementa apenas os dois primeiros:

| Workflow                              | Status            |
|----------------------------------------|------------------|
| Produto Novo (Greenfield)               | ✅ implementado  |
| Funcionalidade Nova (Brownfield)        | ✅ implementado  |
| Vibecoding                              | 🔜 backlog       |
| Regulatórios                            | 🔜 backlog       |
| Bugs em Produção                        | 🔜 backlog       |

Os 3 workflows em backlog estão documentados aqui apenas para registro —
**não há comandos, aliases ou selectors implementados para eles** nesta
feature.

## 3. Sequências GF e BF (upstream) + downstream compartilhado

### Greenfield (Produto Novo) — UPSTREAM

```
generate-project-context → brainstorm → research(opt) → create-product-brief →
create-prd → create-ux-design → create-architecture → testarch-test-design →
create-epics-and-stories → check-impl-readiness(opt)
```

### Brownfield (Funcionalidade Nova) — UPSTREAM

```
generate-project-context → create-prd → create-ux-design → create-architecture →
testarch-test-design → create-epics-and-stories → check-impl-readiness(opt)
```

### DOWNSTREAM (compartilhado pelos dois)

```
testarch-framework → testarch-ci → sprint-planning → create-story →
testarch-atdd → dev-story → code-review → correct-course →
testarch-automate(opt) → retrospective
```

O selector `/bmad <gf|bf>` executa a sequência upstream escolhida e, ao
final, **pára obrigatoriamente** para confirmação explícita do usuário antes
de iniciar o downstream (que dispara Waves de desenvolvimento). O gate de
`check-impl-readiness` (que delega a `/check-readiness`, F10) decide se o
downstream pode começar: se `BLOCKED`, o selector pára antes de avançar.
Passos marcados `(opt)` são oferecidos, não forçados. O selector não
reimplementa Gandalf (t800) nem o gate TEA (F13) — apenas invoca os comandos
que já os disparam.

## 4. Tabela alias → base → agente → estado

| Alias                          | Base didio                          | Persona | Fase       | Agente didio | Estado     |
|---------------------------------|--------------------------------------|---------|------------|--------------|------------|
| `bmad-brainstorm`                | `/brainstorm` (F14)                  | PB      | upstream   | architect    | existente  |
| `bmad-research`                  | `/research` (F14)                    | PB      | upstream   | architect    | existente  |
| `bmad-create-product-brief`      | `/product-brief` (F14)               | PB      | upstream   | architect    | existente  |
| `bmad-create-prd`                | `/elicit-prd` (F11)                  | PB      | upstream   | architect    | existente  |
| `bmad-check-impl-readiness`      | `/check-readiness` (F10)             | AIE     | upstream   | architect    | existente  |
| `bmad-create-architecture`       | `/plan-feature` (PLAN_ONLY)          | AIE     | upstream   | architect    | existente  |
| `bmad-testarch-test-design`      | `/check-tests` (tea, F13)            | QE      | upstream   | tea          | existente  |
| `bmad-create-epics-and-stories`  | `/plan-feature` (output Architect)   | AIE     | upstream   | architect    | existente  |
| `bmad-create-story`              | `/plan-feature` (geração de task)    | AIE     | upstream   | architect    | existente  |
| `bmad-dev-story`                 | `didio run-wave` / `developer`       | AIE     | downstream | developer    | existente  |
| `bmad-code-review`               | `/code-review` / `techlead`          | QE      | downstream | techlead     | existente  |
| `bmad-retrospective`             | retrospectiva embutida no QA         | QE      | downstream | qa           | existente  |
| `generate-project-context`       | (comando novo)                       | PB/AIE  | upstream   | architect    | novo (F27) |
| `create-ux-design`                | (comando novo)                       | AIE     | upstream   | architect    | novo (F27) |
| `testarch-framework`              | (comando novo)                       | QE      | downstream | tea          | novo (F27) |
| `testarch-ci`                     | (comando novo)                       | QE      | downstream | tea          | novo (F27) |
| `sprint-planning`                  | (comando novo)                       | AIE     | downstream | architect    | novo (F27) |
| `testarch-atdd`                    | (comando novo)                       | QE      | downstream | tea          | novo (F27) |
| `correct-course`                   | (comando novo)                       | AIE     | downstream | developer    | novo (F27) |
| `testarch-automate`                | (comando novo, opt)                  | QE      | downstream | tea          | novo (F27) |
| `bmad <greenfield\|brownfield>`    | selector — encadeia os comandos acima| —       | —          | —            | novo (F27) |

Notas:
- `bmad-create-architecture`, `bmad-create-epics-and-stories` e
  `bmad-create-story` delegam todos a `/plan-feature` — o Architect já
  produz arquitetura + epics-as-tasks + stories num só passo. São aliases
  distintos pela semântica BMAD, mas o `delegates-to` é o mesmo.
- `bmad-dev-story`, `bmad-code-review` e `bmad-retrospective` delegam a ações
  que hoje são spawns (`didio run-wave`, agente `techlead`, cerimônia do
  `qa`) — ainda é delegação, não reimplementação.

## 5. Tabela de personas PB/AIE/QE → agentes didio

| Persona BMAD | Significado              | Mapeia em (didio)                                                          |
|--------------|--------------------------|------------------------------------------------------------------------------|
| **PB**       | Product / plano          | `architect` (via `/brainstorm`, `/research`, `/product-brief`, `/elicit-prd`) |
| **AIE**      | Arquitetura / impl       | `architect` + `developer` (via `/plan-feature`, `didio run-wave`)             |
| **QE**       | Test design / validação  | `tea` + `qa` (via `/check-tests`, `/code-review`, retrospectiva)              |

Nenhum agente novo foi criado em `templates/agents/prompts/` — as 3 personas
BMAD reutilizam integralmente os agentes existentes do pipeline didio.

## 6. Propagação (sync) e menu

- Os comandos `/bmad-*` e os comandos novos vivem em `templates/commands/` e
  são propagados para projetos downstream via `didio-sync-project.sh`,
  seguindo o padrão F04/F08 (não destrutivo: arquivos já existentes no
  downstream nunca são sobrescritos).
- **Permissões:** nenhuma permissão nova de `settings.json` é introduzida pelo
  modo BMAD. A task F27-T03 (que adicionaria `Write(claude-didio-out/**)`) foi
  **descartada** (decisão 2026-06-10): bateu no lock de segurança do F15
  (agents spawnados não editam `.claude/settings*.json`) e é não-essencial — os
  comandos `/bmad-*` rodam no contexto main e pedem permissão de escrita como os
  comandos F14 (`/brainstorm`, `/research`) já fazem. Quem quiser evitar o prompt
  pode adicionar `Write(claude-didio-out/**)` manualmente via `/update-config`.
- O menu `/didio` ganha uma entrada BMAD (AC5), mas `didio.md` é customizado
  por projeto e **não é propagado pelo sync** — cada downstream mantém seu
  próprio menu. Isso é esperado e consistente com o comportamento atual do
  sync (ver `docs/diagrams/F27-architecture.mmd` para a visão de camadas).
