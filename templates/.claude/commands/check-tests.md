---
description: Audita cobertura de testes de uma feature — compara test-plan.md do TEA contra testes implementados
argument-hint: <FXX>
---

Você é um auditor de qualidade de testes para o projeto **{{PROJECT_NAME}}**.

Feature a auditar: **$ARGUMENTS**

## Sua missão

Verificar se os testes implementados para a feature cobrem o que o TEA planejou em `<FXX>-test-plan.md`.

## Passo 1 — Localizar artefatos

```
tasks/features/<FXX>-*/
  <FXX>-README.md       — acceptance criteria
  <FXX>-test-plan.md   — plano do TEA (se existir)
  <FXX>-T*.md          — tasks implementadas
```

Se `<FXX>-test-plan.md` não existir, TEA não rodou para esta feature. Reporte isso e prossiga auditando apenas os acceptance criteria do README.

## Passo 2 — Mapear testes existentes

Para cada test file listado no test-plan.md (seção "Test File Map"):
1. Verifique se o arquivo existe no disco
2. Leia o arquivo e identifique quais cenários estão cobertos
3. Compare com os cenários esperados no test-plan.md (seção "Coverage Map")

Se não há test-plan.md, busque test files relacionados à feature via:
```bash
grep -r "F<NN>\|<feature-slug>" blind-warrior-frontend/src --include="*.test.*" -l
grep -r "F<NN>\|<feature-slug>" blind-warrior-backend/src/test -l 2>/dev/null
```

## Passo 3 — Verificar fixtures

Para cada fixture listado no test-plan.md:
- Existe em `tests/fixtures/`?
- É importado pelos test files corretos?

## Passo 4 — Verificar performance budgets

Para cada budget no test-plan.md:
- Existe algum teste com `fake timers` ou assertions de latência?
- Se não, é um gap de cobertura.

## Passo 5 — Relatório

Produza um relatório no formato:

```markdown
# Test Audit — <FXX>: <Feature Title>

**Data:** <YYYY-MM-DD>
**TEA plan presente:** sim/não

## Cobertura por Acceptance Criterion

| CA | Esperado | Implementado | Status |
|----|----------|--------------|--------|
| CA01 | <cenários TEA> | <testes encontrados> | ✅ / ⚠️ / ❌ |

## Gaps detectados

- ❌ <cenário ausente>: não encontrado em nenhum test file

## Fixtures

- ✅ / ❌ `tests/fixtures/<path>` — presente/ausente

## Performance Budgets

- ✅ / ❌ <operação> < <budget>ms — testado/não testado

## Sumário

| Total CAs | Cobertos | Parciais | Ausentes |
|-----------|----------|----------|---------|
| N | N | N | N |

**Recomendação:** APPROVED / GAPS FOUND (lista de ações)
```

Salve o relatório em `tasks/features/<FXX>-*/check-tests-<data>.md` e mostre ao usuário.

---

(c) 2026 Blind Studios. Todos os direitos reservados.
