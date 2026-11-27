# ADR-0013: War Room Promotion Directory Fix + Triage Consolidation

## Status

Accepted

**Date:** 2026-11-26
**Feature:** F35

## Context

The `didio blackhawk promote` CLI command (in `bin/didio-blackhawk-promote.sh`,
lines 168-193) created a **loose file** (`tasks/features/FXX-_tmp-brief.md`)
instead of the directory structure that the Architect agent expects
(`tasks/features/FXX-<slug>/FXX-README.md`). This broke the entire
promotion-to-pipeline bridge: promoted War Room cards could never enter the
standard feature pipeline because the Architect scans for
`tasks/features/FXX-*/FXX-README.md`.

Additionally, the promote logic was duplicated across three locations:

| Location | Behavior |
|---|---|
| `bin/didio-blackhawk-promote.sh` `cmd_promote()` | Created loose file (broken) |
| `bin/didio-blackhawk-triage.sh` `promote_card()` L366-425 | Created correct directory (inline, untestable) |
| `lib/blackhawk-triage.sh` `promote_card()` L403-406 | Delegated to CLI (broken) |

This meant the triage batch flow accidentally worked (it had its own inline
implementation) while the direct CLI path was broken -- a subtle divergence
that would have caused confusion in production use.

## Decision

### 1. Promote creates directory + README

The `cmd_promote()` function in `bin/didio-blackhawk-promote.sh` was fixed to:

1. Generate a filesystem-safe slug from the card title (via existing `_slugify`)
2. Create directory: `tasks/features/${feature_id}-${slug}/`
3. Create README: `tasks/features/${feature_id}-${slug}/${feature_id}-README.md`
4. Check for directory collision (`-d "$feature_dir"`) instead of file collision

This matches the contract the Architect agent expects and enables the full
War Room -> Triage -> Promote -> Pipeline flow.

### 2. Consolidate duplicated triage logic into lib/

The inline `promote_card()` in `bin/didio-blackhawk-triage.sh` was removed.
Both the triage batch flow and the direct CLI now delegate to the single
implementation in `bin/didio-blackhawk-promote.sh`. The library
`lib/blackhawk-triage.sh` delegates to the CLI, which is now correct.

## Consequences

### Positive

- **Single source of truth** -- one promote implementation in
  `bin/didio-blackhawk-promote.sh`; no inline duplicates
- **Pipeline-compatible** -- promoted cards produce the exact directory
  structure the Architect agent scans for
- **Testable** -- the E2E test (`tests/F35-promote-e2e.sh`) validates the
  full card-create -> assess -> promote -> verify-directory flow
- **Backwards-compatible** -- existing card JSON schema unchanged; only the
  output artifact format changed from file to directory

### Negative

- **Orphan cleanup needed** -- any existing `*-_tmp-brief.md` files from
  prior broken promotes remain on disk. These are not auto-deleted (operator
  should decide); the runbook documents how to identify and clean them up
- **Schema coupling** -- the README template in `cmd_promote()` must stay
  aligned with what the Architect expects; a future change to the Architect's
  scan pattern requires updating the promote output

### Risks

- Promote directory collisions if two operators promote different cards to the
  same feature ID simultaneously -- mitigated by `_next_feature_id()` scanning
  existing directories before allocation
