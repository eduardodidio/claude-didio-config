# ADR-0004: Multi-provider driver architecture

**Status:** accepted
**Date:** 2026-06-13
**Deciders:** @eduardodidio

## Context

`claude-didio-config` is today 100% coupled to Claude Code: every agent role
(architect, developer, techlead, qa, readiness, tea, meeting-parser, t800,
t1000, narrative-designer) is launched by `didio-spawn-agent.sh` with a
hardcoded `claude -p ... --output-format stream-json ...` invocation. Every
downstream consumer of the resulting JSONL (dashboard, rate-limit handling,
error detection, retrospectives) assumes Claude's `stream-json` schema.

F01 introduces a second supported provider — the **OpenAI Codex CLI**
(`codex exec`, headless) — and requires each role to be independently
assignable to either provider, while reusing all existing engineering (Waves,
spawn-agent, rate-limit handling, dashboard, JSONL logs, readiness/TEA gates,
retrospectives) rather than rewriting orchestration.

## Decision

Extract the hardcoded `claude -p` invocation out of `didio-spawn-agent.sh`
into pluggable **provider drivers** under `drivers/`:

- `drivers/claude-driver.sh` — wraps the existing `claude -p ...
  --output-format stream-json` invocation, unchanged in behavior.
- `drivers/codex-driver.sh` — wraps `codex exec` in headless mode and emits
  NDJSON events normalized to the same downstream contract.

`didio-spawn-agent.sh` resolves the provider for a role (via
`didio-config-lib.sh`, project-local-first then global), defaults to
`claude` when unset, and dispatches to the matching driver. The driver
contract is: read a prompt, run the provider CLI, stream NDJSON events to the
existing log pipeline (`logs/agents/*.jsonl`).

## Consequences

- **Backward compatibility (AC3):** when no `provider` is configured for a
  role, the Claude-only flow is byte-for-byte unchanged — `claude-driver.sh`
  is a thin wrapper around the prior inline invocation.
- **NDJSON schema divergence** between Claude's `stream-json` and Codex's
  `exec` output is handled by a normalizer (task T11), which maps both
  schemas onto a single internal event shape consumed by the dashboard,
  rate-limit detector, and error detector.
- **Codex has no fallback/effort flags** equivalent to Claude's
  `--fallback-model` / reasoning-effort controls. This is a documented gap:
  Codex-assigned roles run without those controls until/unless Codex exposes
  an equivalent.
- Adding a third provider in the future means adding one more
  `drivers/<provider>-driver.sh` plus a normalizer mapping — the
  spawn-agent/Wave/dashboard layers do not change.

## Alternatives considered

- **API-direct integration** (calling OpenAI/Anthropic APIs directly instead
  of the Codex/Claude CLIs) — rejected as a non-goal; the CLI-driver model
  reuses existing auth, rate-limit, and session handling that the CLIs
  already provide.
- **Rewrite orchestration in Python** — rejected as a non-goal; the existing
  bash-based Waves/spawn-agent engineering is reused as-is, only the
  provider-specific invocation is abstracted.
- **Support providers beyond Claude + Codex now** — rejected as a non-goal
  for F01; the driver abstraction makes future providers additive, but only
  Claude and Codex are implemented in this feature.
