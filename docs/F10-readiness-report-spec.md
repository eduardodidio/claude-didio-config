# F10 — Readiness Report Spec (output contract)

**Audience:** o agent `readiness` (escreve o report) e o slash command
`/check-readiness` (parseia o veredito).

## Path

```
tasks/features/<FXX>-*/readiness-report.md
```

## Required structure

````markdown
# Readiness Report — <FXX> <slug>

**Generated:** <YYYY-MM-DDTHH:MM:SSZ>
**Feature dir:** tasks/features/<FXX>-*/
**Total tasks audited:** <N>
**Total ACs declared:** <M>

## Check 1 — AC coverage (every AC has ≥1 task)
| AC ID | Status | Tasks covering | Detail |
|-------|--------|----------------|--------|
| AC1   | PASS   | T03, T07       |        |
| AC4   | FAIL   | (none)         | AC4 declarado em README mas nenhuma task cita |

## Check 2 — Bidirectional traceability (every task cites ≥1 AC)
| Task | Status | ACs cited | Detail |
|------|--------|-----------|--------|
| T01  | PASS   | AC10      |        |
| T05  | FAIL   | (none)    | task sem campo `**Maps to AC:**` |

## Check 3 — File collision (same-Wave tasks don't share files)
| Wave | Status | Colliding paths | Tasks involved |
|------|--------|-----------------|----------------|
| 1    | PASS   | (none)          |                |
| 2    | FAIL   | src/foo.ts      | T06, T07       |

## Check 4 — Wave 0 completeness (deps/perms/scaffolding)
| Item needed by Wave≥1 | Status | Wave 0 covers? | Detail |
|------------------------|--------|----------------|--------|
| `mkdir tests/F10-fixtures` | FAIL | no | T08 menciona criar dir; Wave 0 não cria |

## Check 5 — Testing section non-empty
| Task | Status | Detail |
|------|--------|--------|
| T01  | PASS   |        |
| T05  | FAIL   | seção `## Testing` vazia ou `_TODO_` |

## Summary
- PASS: <X>
- FAIL: <Y>

**Verdict:** READY
````

(or `**Verdict:** BLOCKED` — exact strings, no quotes, exact case)

## Parser contract (slash command)

Last occurrence of `^**Verdict:** (READY|BLOCKED)$` na primeira coluna define
o veredito.

- Regex: `/^\*\*Verdict:\*\* (READY|BLOCKED)$/m`
- Veredito ausente ou report inexistente → tratar como `BLOCKED` com motivo
  `"report malformado"`.
- Comparação é case-sensitive. `ready` ou `blocked` em minúsculas **não** são
  aceitos.

## Check definitions

| # | Check name | Pass condition |
|---|------------|----------------|
| 1 | AC coverage | Every AC ID declared in README has ≥1 task with `**Maps to AC:**` citing it |
| 2 | Bidirectional traceability | Every task file has a non-empty `**Maps to AC:**` field |
| 3 | File collision | No two tasks in the same Wave list the same output file path |
| 4 | Wave 0 completeness | Every dir, permission, env var, or dep mentioned by Wave≥1 tasks is created/declared by a Wave 0 task |
| 5 | Testing non-empty | Every task has a `## Testing` section with content (not `_TODO_` or blank) |

Overall verdict is `READY` only when **all 5 checks** produce zero FAILs.
Any single FAIL → `BLOCKED`.
