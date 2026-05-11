---
description: Audit pré-Wave de uma feature planejada (verdict READY/BLOCKED em ~30s)
argument-hint: <FXX>
---

# /check-readiness — Pre-Wave plan audit

You are running the readiness gate for this project.

The user asked to audit feature: **$ARGUMENTS**

## Step 1 — Validate input

Check that `$ARGUMENTS` matches the pattern `F[0-9]+` (e.g. `F10`). If not,
print an error and exit.

Find the feature directory: `tasks/features/<FXX>-*/` must exist.
Find the README: `tasks/features/<FXX>-*/<FXX>-README.md` must exist.
If either is missing, print an error and stop.

## Step 2 — Bypass check

If env var `DIDIO_SKIP_READINESS=1` is set:
- Print: `⚠️  DIDIO_SKIP_READINESS=1 — skipping readiness audit`
- Exit 0 (bypass approved by operator)

## Step 3 — Pre-condition

Read the README header. If `**Status:** planned` is NOT present, print:

```
ℹ️  /check-readiness skipped: <FXX> status is not "planned"
```

And exit 0 — only planned features need the audit.

If env var `DIDIO_READINESS_FORCE=1` is set, skip this check and proceed even
for non-planned features (debug/sanity use only). Add to the report header:
`**Forced run:** DIDIO_READINESS_FORCE=1 (status was: <actual>)`

## Step 4 — Spawn readiness agent

```bash
didio spawn-agent readiness <FXX> tasks/features/<FXX>-*/<FXX>-README.md
```

Wait for the agent to write `tasks/features/<FXX>-*/readiness-report.md`.

## Step 5 — Parse verdict

Read `tasks/features/<FXX>-*/readiness-report.md`.
Extract the line matching `**Verdict:** READY` or `**Verdict:** BLOCKED`.
If the file is missing or the verdict line is absent, treat as BLOCKED.

## Step 6 — Report to user

Print a colored summary:
- READY → green `✅ READY — proceed to Wave 0`
- BLOCKED → red `❌ BLOCKED — see tasks/features/<FXX>-*/readiness-report.md`

## Bypass de emergência

```bash
DIDIO_SKIP_READINESS=1 /check-readiness F10
```

Use when you need to skip the audit. This does NOT run the agent.

## Rules

- DO NOT modify task files.
- DO NOT spawn TechLead/QA from here.
- ALWAYS exit non-zero (exit 1) on BLOCKED so the caller (orchestrator) can abort.
