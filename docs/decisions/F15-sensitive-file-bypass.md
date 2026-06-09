# ADR: F15 — Sensitive-file bypass for headless agents

**Date:** 2026-04-27
**Status:** Accepted
**Feature:** F15-sensitive-file-bypass-headless

---

## Context

`bin/didio-spawn-agent.sh` invokes `claude -p --dangerously-skip-permissions` in headless mode. Despite the flag, Claude Code's sensitive-file protection silently denies `Edit`/`Write` on any path under `.claude/`. The agent's tool result carries `is_error=True` with the message "Claude requested permissions to edit … which is a sensitive file", but the conversation ends as `result.subtype=success`, so the spawn script exits 0 and the wave-runner records the task as done.

This silent-failure pattern bit the project on five separate occasions: F10-T06, F10-T07, F11-T05, F13-T04, and F14-T02/T03 — every one flagged BLOCKING by TechLead and resolved only by manual operator patches. Two bugs are at play: (1) headless agents cannot edit `.claude/**` regardless of the `--dangerously-skip-permissions` flag, and (2) `didio-spawn-agent.sh` trusts the CLI exit code, which is 0 even when every tool call errored.

F15-T01 spike confirmed that `--dangerously-skip-permissions` does **NOT** bypass the sensitive-file guard; the guard is a separate protection layer enforced unconditionally on top of the permission system.

---

## Decision

**Implemented (partially effective):** Pass `--allowedTools "Edit Write MultiEdit Read Bash Glob Grep"` explicitly to the `claude -p` invocation in `bin/didio-spawn-agent.sh`. The `DIDIO_AGENT=1` environment variable is exported by spawn-agent as a sentinel for future hook branching. **However:** the F15-T05 smoke test subsequently proved that `--allowedTools` does NOT bypass the sensitive-file guard for paths containing `.claude/` as a component (including `templates/.claude/commands/**`). The guard is enforced at a layer independent of the tool allowlist. Approach C (restructuring the path to avoid `.claude/`) is the planned next step, tracked in F15-T08.

**Fully effective:** `bin/didio-spawn-agent.sh` parses the run's JSONL output after `claude -p` returns (via `bin/didio-jsonl-errors.py`). If any `tool_result` event contains `is_error: true` and the CLI exit code was 0, the script overrides the exit code to 2 (`EXIT_CODE=2`) and sets `FINAL_STATUS=failed`. Exit code 2 is distinct from 1 (CLI usage error). This makes JSONL the ground truth rather than the CLI exit code. This fix ships independently of the permission-bypass issue and is immediately beneficial.

`.claude/settings.json` remains protected. The sensitive-file guard applies unconditionally to all paths under `.claude/`, regardless of `--allowedTools` or hook output.

---

## Alternatives considered

- **A — PreToolUse hook `permissionDecision: "allow"` for `.claude/commands/**` paths when `DIDIO_AGENT=1`**: rejected because F15-T01 spike proved that the sensitive-file guard runs independently of hook output. The hook received the call, returned `allow`, and the file was still not written. The guard is applied at a separate layer that cannot be overridden via the hook permission mechanism.

- **B — `--permission-mode acceptEdits`**: rejected because `acceptEdits` is a semantic alias of `bypassPermissions`/`--dangerously-skip-permissions`, which is already in use. Switching modes provides no additional bypass capability over the current invocation; the sensitive-file guard applies regardless of which bypass mode is active.

- **C — Move slash-command files to a path without `.claude/` as a component (rename `templates/.claude/commands/` → `templates/commands/`; update `.claude/commands` symlink to point to `templates/commands/`)**: initially deferred because it appeared to require a coordinated migration across downstream projects. After Approach A also failed (F15-T05 smoke confirmed `--allowedTools` does not bypass the sensitive-file guard), Approach C was implemented in F15-T08 — the rename preserves the `.claude/commands` symlink for downstream resolution while the canonical write target moves outside `.claude/`. **This is the fix that ships with F15.**

- **D — `settings.local.json` explicit allow rule for `Edit(.claude/commands/**)` paths**: rejected because the sensitive-file guard sits above the allow-list layer and is evaluated unconditionally before allow rules are consulted. An allow rule in `settings.local.json` cannot override a sensitive-file denial, making this approach a no-op for this class of protected paths.

---

## Consequences

- Downstream projects inherit the fix on the next `didio-sync-project.sh` run, which syncs `bin/didio-spawn-agent.sh` and `bin/hooks/`.
- `.claude/settings.json` remains locked — the `--allowedTools` flag is tool-scoped, not path-scoped. Settings files are protected by the sensitive-file guard, which still applies to any tool not in the allowlist or to tools operating on sensitive paths outside the explicit allow scope.
- Future expansions of the allowlist (e.g., allowing agents to edit `.claude/agents/**`) require a new ADR amendment and a review of the blast radius of the change.
- Spawn-agent's exit-code semantics are now "any tool error fails the run." Workflows that need to tolerate benign tool errors (e.g., a file-not-found that the agent handles gracefully) may need a `DIDIO_TOLERATE_TOOL_ERRORS=1` env var in a future follow-up.
- The `DIDIO_AGENT=1` sentinel is exported on every spawn-agent invocation. Future hooks or scripts can branch on this variable to distinguish spawned-agent context from interactive context without adding new infrastructure.

---

## Addendum — 2026-06-09: CLI behavior changed, settings.json lock re-implemented

**Regression discovered.** The F15-T01 spike (2026-04-27) established that
Claude Code's built-in sensitive-file guard blocks any `Edit`/`Write` under
`.claude/` *unconditionally*, even with `--dangerously-skip-permissions`. The
"Consequences" section above relied on that: "`.claude/settings.json` remains
locked … protected by the sensitive-file guard."

Re-running `tests/F15-sensitive-edit.sh` on 2026-06-09 proved that behavior
**no longer holds**. A spawned agent (`--dangerously-skip-permissions`)
successfully wrote `"_f15_should_be_denied": true` into `.claude/settings.json`
(md5 changed, `is_error:false`, spawn exit 0) — and even retried with a second
key. The CLI now lets skip-permissions bypass the `.claude/` guard, so AC8 was
silently failing. Because `.claude/settings.json` defines hooks and
permissions, a spawned agent could rewrite it → privilege-escalation /
persistence vector.

**Decision.** Stop relying on the CLI's emergent guard. Enforce the lock
ourselves in `bin/hooks/didio-pre-tool.sh`: when `DIDIO_AGENT=1` and the tool
is `Edit`/`Write`/`MultiEdit` targeting `.claude/settings.json` or
`.claude/settings.local.json`, emit a PreToolUse `permissionDecision:"deny"`
and exit 2. A hook deny **is** honored under `--dangerously-skip-permissions`
(it's the same mechanism the F07 session-guard budget-deny uses). The check
runs **before** the guard's bypass valves (`DIDIO_BYPASS_GUARD`, the
`.guard-bypass` kill-switch) so the budget escape-hatches can never also unlock
settings.json for an agent. It is scoped to `DIDIO_AGENT=1`, so the operator's
interactive session can still edit its own settings (e.g. via `/update-config`).

**Verification.** `tests/F15-sensitive-edit.sh` AC4+AC8 now pass end-to-end
(settings.json byte-identical, spawn exits 2). `tests/F15-pre-tool-unit.sh`
gains 5 lock cases (deny for agent, allow for human, allow for
`templates/commands/`, deny-under-bypass hardening). All 25 unit assertions
pass.

**Propagation.** The hook is referenced by absolute / `${DIDIO_HOME}` path from
each downstream `.claude/settings.json`, so all 5 downstreams inherit the fix
with no copy to sync.
