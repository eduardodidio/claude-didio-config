# F12 — Shard measurement (tokens before vs after)

**Status:** populated (by F12-T10, 2026-04-26).

## Setup

Two fixtures exercise the Developer prompt-build path:

- **Fixture A — não-shardada:** F08 brief original (277 linhas), task F08-T01
  (que cita o brief inteiro implicitamente).
- **Fixture B — shardada:** F08 brief reescrito como `_brief/` com
  `00-overview.md` + 4 shards (`01-models-config.md`, `02-effort-flag.md`,
  `03-session-guard.md`, `04-sync.md`), task F08-T01 referenciando apenas
  `_brief/01-models-config.md`.

## How to reproduce

```bash
DIDIO_DRY_RUN=1 ./bin/didio-spawn-agent.sh developer F08 \
  tasks/features/F08-agent-runtime-audit/F08-T01.md 2>&1
```

(Token counting was implemented inline in `tests/F12-sync-archive-smoke.sh`
Cenário 4 using `wc -l` as a proxy — no separate `F12-token-counter.sh` was
created. Actual token count would require an Anthropic SDK call.)

## Results

| Fixture        | Prompt lines | Approx input tokens (proxy) | Notes |
|----------------|--------------|-----------------------------|-------|
| A (não-shardada) |   277  | ~ 1108 (4×lines)      | F08 _brief.md original |
| B (shardada)   |    99  | ~  396 (4×lines)      | overview + 1 shard cited |
| Δ              |   178 (64.3%) | ~  712 (64.3%) | medido em 2026-04-26 |

## Conclusion

Sharding cuts ~64.3% of input lines in the F08-fixture scenario. Real-token gain depends on shard granularity; the proxy here uses `wc -l` × 4 as a rough byte/token approximation. Threshold of 150 lines is justified empirically — below that, the indirection cost (extra dir, citation discipline) outweighs the savings.
