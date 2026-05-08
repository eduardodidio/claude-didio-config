# F22 Test Fixtures

Hermetic JSONL fixtures and a mock `claude` binary for F22 rate-limit auto-resume tests.
These fixtures are referenced by F22-T02, T08, T10 tests. Do NOT modify without updating those tests.

## Fixtures

| File | Description |
|------|-------------|
| `rate-limit-brt-am.jsonl` | Rate-limit hit; resets at 11:20am America/Sao_Paulo (BRT, am format) |
| `rate-limit-est-pm.jsonl` | Rate-limit hit; resets at 4:05pm America/New_York (EST, pm format) |
| `rate-limit-utc-24h.jsonl` | Rate-limit hit; resets at 09:00 UTC (24-hour format, no am/pm) |
| `success.jsonl` | Successful run; `is_error:false`, result "Task completed successfully" |
| `real-error.jsonl` | Non-rate-limit error; `is_error:true`, "Permission denied" message (no rate-limit markers) |
| `unknown-no-result.jsonl` | Incomplete stream — process killed mid-run; no `result` event (classifier returns `unknown`) |

## mock-claude.sh

Stand-in for `claude -p --output-format stream-json`. Accepts and ignores all standard `claude` CLI flags.

**Usage:**
```bash
export MOCK_CLAUDE_FIXTURE=success.jsonl          # required: basename of fixture to emit
export MOCK_CLAUDE_EXIT=0                          # optional: exit code (default 0)
./mock-claude.sh -p --output-format stream-json   # flags are silently ignored
```

**PATH injection pattern** (used by T08):
```bash
export PATH="$FIXTURES_DIR/bin:$PATH"
# bin/claude is a symlink to ../mock-claude.sh
```

## Notes

- No fixture contains real API keys, real webhook URLs, or real user data. All values are synthetic.
- F08 lesson: if any test involves hooks, export `DIDIO_HOOKS_DISABLE_FILTER=1` to bypass the hook
  filter and prevent false positives. This fixture set does not fire hooks, but the precedent is
  documented here for test authors who extend these fixtures.
- Each fixture lives in its own file — no cross-contamination (F17 hermetic-fixture lesson).
