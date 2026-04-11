# Diagramas

Esta pasta é documentação viva. Toda feature MUST produzir ao menos
dois diagramas Mermaid aqui:

## Obrigatórios (por feature)

1. **`<FXX>-architecture.mmd`** — arquitetura / data flow
   Mostra quais módulos/camadas foram tocados e como dados fluem.
   Template: [`templates/architecture.mmd`](templates/architecture.mmd).

2. **`<FXX>-journey.mmd`** — jornada do usuário (BPMN-style)
   Mostra o fluxo que o usuário percorre, decisões e erros.
   Template: [`templates/user-journey.mmd`](templates/user-journey.mmd).

## Opcionais (quando ajudarem)

- `<FXX>-sequence.mmd` — diagramas de sequência (interações temporais)
- `<FXX>-state.mmd` — máquina de estados
- `<FXX>-er.mmd` — relações de dados

## Convenções

- Nome do arquivo começa com o id da feature (`F0X-`)
- Use `flowchart LR` pra arquitetura, `flowchart TD` com swimlanes
  via `subgraph` pra jornadas BPMN-style
- Atualize o `INDEX.md` quando adicionar um novo diagrama
- Diagramas batem com a realidade do código — se o código mudou e o
  diagrama não, é bug: o TechLead ou o QA devem rejeitar
