# /elicit-prd — Question template

**Versão:** 1
**Status:** stable
**Última revisão:** 2026-04-26

Este arquivo é a **única** fonte de verdade das perguntas conduzidas
pelo slash command `/elicit-prd`. Editar aqui muda o comportamento do command.

## Q1 — Problema/dor

- **id:** problem
- **prompt:** Qual o problema concreto que essa feature resolve? Quem sente a dor hoje, e como ela aparece?
- **target:** `## Problem` (template.md)
- **required:** true
- **trigger:** always

## Q2 — Persona / quem usa

- **id:** persona
- **prompt:** Quem é o usuário principal? Há perfis secundários?
- **target:** `## Problem` (template.md, parágrafo "Quem é o usuário")
- **required:** true
- **trigger:** always

## Q3 — Fora-de-escopo explícito

- **id:** out_of_scope
- **prompt:** O que essa feature explicitamente NÃO inclui? Liste itens que poderiam ser confundidos com escopo.
- **target:** `## Scope > Out of scope` (template.md)
- **required:** true
- **trigger:** always

## Q4 — Riscos conhecidos

- **id:** risks
- **prompt:** Quais riscos já conhecidos podem ameaçar essa feature? (técnicos, de negócio, de dependência)
- **target:** `## Open questions` (subseção "Riscos conhecidos") (template.md)
- **required:** true
- **trigger:** always

## Q5 — Restrições técnicas

- **id:** constraints
- **prompt:** Há restrições técnicas (linguagem, framework, infra, versão) que a solução deve respeitar?
- **target:** `## Open questions` (subseção "Restrições") (template.md)
- **required:** true
- **trigger:** always

## Q6 — Métrica de sucesso

- **id:** success
- **prompt:** Como saberemos que essa feature funcionou? Qual a métrica ou critério de aceite principal?
- **target:** `## Success metrics` (template.md)
- **required:** true
- **trigger:** always

## Q7 — Dependências upstream

- **id:** dependencies
- **prompt:** Essa feature depende de outra feature ou sistema externo que precisa estar pronto antes?
- **target:** `## Open questions` (subseção "Dependências upstream") (template.md)
- **required:** true
- **trigger:** always

## Q8 — Deadline

- **id:** deadline
- **prompt:** Há uma data-limite ou janela de entrega para essa feature?
- **target:** `## Open questions` (subseção "Deadline") (template.md)
- **required:** true
- **trigger:** always

## C1 — Stakeholders externos (condicional)

- **id:** stakeholders
- **prompt:** Quais stakeholders externos (legal, financeiro, parceiro, cliente) precisam aprovar antes do go-live?
- **target:** `## Open questions` (template.md)
- **required:** false
- **trigger:** persona contains one of (legal|financeiro|parceiro|cliente)

## C2 — Plataforma alvo (condicional)

- **id:** platform
- **prompt:** A feature está atrelada a alguma plataforma específica (mobile/web/CLI/dashboard/API)?
- **target:** `## Scope > In scope` (template.md)
- **required:** false
- **trigger:** title matches /(mobile|web|cli|dashboard|api|agent)/i

## Mapeamento para template.md

| id           | target                                              |
|--------------|-----------------------------------------------------|
| problem      | `## Problem`                                        |
| persona      | `## Problem` (parágrafo "Quem é o usuário")         |
| out_of_scope | `## Scope > Out of scope`                           |
| risks        | `## Open questions` (subseção "Riscos conhecidos")  |
| constraints  | `## Open questions` (subseção "Restrições")         |
| success      | `## Success metrics`                                |
| dependencies | `## Open questions` (subseção "Dependências upstream") |
| deadline     | `## Open questions` (subseção "Deadline")           |
| stakeholders | `## Open questions`                                 |
| platform     | `## Scope > In scope`                               |

## Inferred fields

| id   | síntese                       | fonte   |
|------|-------------------------------|---------|
| goal | síntese de problem + success  | Q1 + Q6 |

O command deriva `## Goal` automaticamente a partir das respostas de Q1 e Q6 — não é pergunta direta ao usuário.
