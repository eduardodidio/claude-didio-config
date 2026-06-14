# Driver Contract

A **driver** is a bash script `${DIDIO_HOME}/drivers/<provider>-driver.sh` that
wraps a single underlying AI CLI (Claude Code, Codex, etc.) so
`didio-spawn-agent.sh` can launch any provider through the same interface.

## Resolution

`didio-spawn-agent.sh` picks the driver script by:

```bash
driver="${DIDIO_HOME}/drivers/$(didio_provider_for_role "$ROLE")-driver.sh"
```

If the resolved file does not exist, spawn-agent must print a clear error and
exit `2`. This naming convention means adding a new provider later requires
zero edits to `didio-spawn-agent.sh`.

## Input (environment variables)

`didio-spawn-agent.sh` exports the following variables before invoking the
driver. Drivers MUST NOT require any other input.

| Variable          | Description                                              |
|--------------------|-----------------------------------------------------------|
| `DIDIO_PROMPT`     | Full composed prompt text (may contain quotes/newlines).  |
| `DIDIO_MODEL`      | Provider-specific model id for this role (may be empty).  |
| `DIDIO_FALLBACK`   | Provider-specific fallback model id (may be empty).        |
| `DIDIO_EFFORT`     | Effort/reasoning level (may be empty).                     |
| `DIDIO_LOG_FILE`   | Absolute path the driver must append NDJSON output to.     |
| `DIDIO_ROLE`       | Agent role name (e.g. `developer`, `architect`).           |
| `DIDIO_FEATURE`    | Feature id (e.g. `F01`).                                    |
| `DIDIO_TASK_ID`    | Task id (e.g. `F01-T02`).                                   |

Empty `DIDIO_MODEL` / `DIDIO_FALLBACK` is a valid input and must not error —
the driver falls back to its underlying CLI's default model selection.

## Output

The driver writes the underlying CLI's native streaming output as NDJSON
(one JSON object per line) to `$DIDIO_LOG_FILE`. The driver itself performs
the redirect (stdout and stderr), exactly like:

```bash
<underlying-cli-invocation> > "$DIDIO_LOG_FILE" 2>&1
```

No driver prints anything to its own stdout/stderr outside of that redirect.

## Exit code

The driver exits with the underlying CLI's exit code. `didio-spawn-agent.sh`
maps any non-zero exit code to a `failed` status.

## Reference implementations

- `claude-driver.sh` — reproduces today's `didio-spawn-agent.sh` invocation
  verbatim (model/fallback/`--output-format stream-json --verbose
  --dangerously-skip-permissions`).
- `codex-driver.sh` — wraps `codex exec --json --yolo`, passing
  `$DIDIO_PROMPT` via stdin.
- `echo-driver.sh` — test fixture (see below).

## Test fixture: `echo-driver.sh`

`echo-driver.sh` is a trivial driver used to validate this contract (and
later the dispatch logic in T07) without spending real model tokens. It:

1. Reads the contract env vars (no required vars beyond `DIDIO_LOG_FILE`).
2. Appends a single canned NDJSON line to `$DIDIO_LOG_FILE`, echoing back
   `DIDIO_ROLE`, `DIDIO_FEATURE`, `DIDIO_TASK_ID`, and the length of
   `DIDIO_PROMPT` (to prove the prompt was received intact, including
   quotes/newlines, without printing it raw).
3. Exits `0`, unless `DIDIO_ECHO_EXIT_CODE` is set, in which case it exits
   with that value (used to test non-zero propagation).
