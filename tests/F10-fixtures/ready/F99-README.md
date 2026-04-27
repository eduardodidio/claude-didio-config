# F99 — Synthetic ready fixture

**Status:** planned
**Waves:** 0..1

## Feature goal

Synthetic fixture with a fully consistent plan. All 5 readiness checks
must pass, producing verdict READY.

## Global acceptance criteria

1. **AC1 — Scaffolding ready:** project structure is created by Wave 0.
2. **AC2 — Core logic implemented:** main module works end-to-end.

## Wave manifest

- **Wave 0**: F99-T01 (scaffolding — serial, blocking)
- **Wave 1**: F99-T02, F99-T03 (implementation — parallel, distinct files)

## Restrições de paralelismo

- Wave 0 é serial e bloqueante.
- Wave 1: T02 toca src/a.ts, T03 toca src/b.ts — sem sobreposição.
