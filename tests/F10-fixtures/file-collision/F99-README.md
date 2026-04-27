# F99 — Synthetic file-collision fixture

**Status:** planned
**Waves:** 0..1

## Feature goal

Synthetic fixture where T02 and T03 (both Wave 1) both declare src/foo.ts.
Check 3 must FAIL with a file collision report.

## Global acceptance criteria

1. **AC1 — Scaffolding ready:** project structure created.
2. **AC2 — Core logic implemented:** main module works.

## Wave manifest

- **Wave 0**: F99-T01 (scaffolding — serial)
- **Wave 1**: F99-T02, F99-T03 (parallel — WARNING: both touch src/foo.ts)
