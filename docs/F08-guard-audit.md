# F08 — Guard Audit: F07 Session Guard Against Acceptance Criteria

**Executed:** 2026-04-24  
**By:** Developer agent, F08-T01 (Wave 0)

---

## Summary Table

| Critério (F07 1-7) | Status | Evidência | Ação |
|--------------------|--------|-----------|------|
| AC1 — Observabilidade: pct atualiza a cada tool call | **FAIL** | `npx ccusage --json` retorna `{"daily":[…],"totals":{…}}`, não `sessions/windows`. Probe parseia `pct=0.0` sempre. Script: `bin/didio-budget-probe.sh:69` | Wave 2: mudar `npx ccusage --json` → `npx ccusage session --json` em `bin/didio-budget-probe.sh` |
| AC2 — Pausa: guard para a wave e escreve `session-paused.json` | **PARTIAL** | Lógica de deny funciona (exit 2 + permissionDecision, Passo 4 PASS). Mas como pct real via ccusage = 0.0, guard nunca dispara naturalmente. Fallback transcript funciona. | Wave 2: depende do fix AC1. Sem fix, guard só ativa via transcript path. |
| AC3 — Checkpoint: `next_action_hint` não-vazio no `.checkpoint.json` | **PASS (code)** | e2e (`tests/F07-pause-resume-e2e.sh`) verifica checkpoint preservation. Código: `post-tool.sh:38` condiciona em `DIDIO_RUN_ID`; `spawn-agent.sh:125` exporta `DIDIO_RUN_ID`. Runtime test com claude-p omitido (risco de invocação aninhada). | Sem ação Wave 2. |
| AC4 — Retomada: scheduled agent relança com prompt RETOMADA | **PASS** | e2e confirmado (13/13 PASS). `resume-scheduled.pid` criado (Passo 5 PASS). `didio-resume-feature.sh` executável. | Sem ação. |
| AC5 — Continuidade: task retomada não repete trabalho | **PASS** | e2e: task-1 resume usa `next_action_hint` preservado do checkpoint; task-2 sem checkpoint usa fallback "Reinicie". LC_ALL=C grep pass. | Sem ação. |
| AC6 — Fallback: guard funciona sem ccusage | **PASS** | smoke test `FAKE_CCUSAGE_FAIL=1` + `DIDIO_TRANSCRIPT_PATH`: probe escreveu `source=transcript, tokens=9600`. Schema válido. | Sem ação. |
| AC7 — Anti-loop: após max_resumes=3, sem novo schedule | **PASS** | e2e: 4ª pausa imprime `max_resumes_per_day`, `resume-scheduled.pid` não criado. | Sem ação. |

---

## Gaps a corrigir (Wave 2)

### Gap #1 (AC1/AC2): ccusage command mismatch — `FAIL` mandatório

**Arquivo:** `bin/didio-budget-probe.sh`, linha 69.

**Problema:** O probe invoca `npx -y ccusage --json` que é equivalente a
`npx ccusage daily --json` e retorna `{"daily":[…],"totals":{…}}`.
A função `parse_ccusage` espera `sessions` ou `windows` no nível raiz;
como não encontra, trata o objeto raiz como `s` e extrai `totalTokens=0`
(não existe nesse nível). Resultado: `pct=0.0` em todo snapshot ccusage,
tornando o guard ineficaz para a fonte primária.

**Fix correto:** Mudar para `npx -y ccusage session --json` que retorna
`{"sessions":[…],"totals":{…}}`. A função `parse_ccusage` existente
parsearia a sessão mais recente (`sessions[-1]`) corretamente, usando
`totalTokens` e `limit_fb` (config `window_limit_tokens`).

**Candidatos para Wave 2:**
- `bin/didio-budget-probe.sh` — trocar invocação ccusage (1 linha)
- `tests/F07-budget-smoke.sh` — adicionar case com shape `session` real
  (FAKE_CCUSAGE_JSON atualmente usa shape `sessions` que *coincide* com
  o fix, então o smoke test validará)

### Gap #2 (AC1/operacional): npx first-run latency — risco operacional

**npx -y ccusage tomou 15s** na primeira invocação (download do pacote).
O PostToolUse hook é síncrono; 15s de latência no primeiro tool call
da sessão é observável pelo usuário. Já documentado na retro F07 §npx.

**Fix opcional Wave 2 (baixa prioridade):** pré-aquecer ccusage com
`npm install -g ccusage` no setup do projeto, ou usar `timeout 5s npx`.

---

## Resumo para Architect da Wave 2

**2/7 critérios FAIL/PARTIAL** → Wave 2 **não pode ser no-op**.

| # | Severidade | Arquivo | Fix |
|---|-----------|---------|-----|
| 1 | **Mandatório** | `bin/didio-budget-probe.sh:69` | `npx -y ccusage --json` → `npx -y ccusage session --json` |
| 2 | Recomendado | `tests/F07-budget-smoke.sh` | Adicionar shape real de ccusage no smoke test |
| 3 | Opcional | `bin/didio-budget-probe.sh` | `timeout 5s npx` para evitar 15s first-run |

Wave 2 = dividir F08-T04 em:
- **F08-T04a**: fix probe invocation (`bin/didio-budget-probe.sh`)  
- **F08-T04b**: fix smoke test shape (`tests/F07-budget-smoke.sh`)

---

## Evidência raw

### Suíte smoke (F07-budget-smoke.sh)

```
EXIT=0 (14/14 PASS)

=== F07 smoke tests ===
--- 1. didio_read_config_path ---
  [PASS] hard_pct=0.98
  [PASS] enabled=true
  [PASS] missing returns default
  [PASS] empty config path returns default
--- 2. Budget probe ---
  [PASS] probe wrote session-budget.json
  [PASS] ccusage JSON parsed correctly
  [PASS] probe throttled within window
  [PASS] transcript fallback: source=transcript
  [PASS] transcript token sum = 9600
--- 3. PreToolUse hook (allow/warn/deny) ---
  [PASS] pct=0.5 → silent allow
  [PASS] pct=0.92 → warn with systemMessage
  [PASS] pct=0.99 → deny with permissionDecision JSON + exit 2
  [PASS] stale pct=0.99 fixture ignored (staleness guard)
--- 4. PostToolUse safe ---
  [PASS] PostToolUse safe on empty stdin
================================
Results: 14 passed, 0 failed
All smoke tests passed.
```

### Suíte e2e (F07-pause-resume-e2e.sh)

```
EXIT=0 (13/13 PASS)

=== F07 pause/resume e2e ===
--- 1. Setup: spawn shim + fake running agents ---
  [PASS] fake agents + state.json + meta files seeded
--- 2. Fire pause (pct=0.99) ---
  [PASS] pause.sh wrote session-paused.json
--- 3. Running agents stopped + meta updated ---
  [PASS] PID1 stopped by SIGTERM
  [PASS] PID2 stopped by SIGTERM
  [PASS] meta-1 status=paused
  [PASS] resume-scheduled.pid captured
--- 5. Resume drives spawn with RETOMADA extra ---
  [PASS] spawn shim invoked 2 times (>= 2 paused tasks)
  [PASS] spawn includes 'RETOMADA DE SESSÃO' extra prompt
  [PASS] task-1 resumed with checkpoint next_action_hint
  [PASS] task-2 fallback to restart (no checkpoint)
  [PASS] session-paused.json renamed to .handled-<ts>
--- 6. Anti-loop (max_resumes_per_day=3) ---
  [PASS] 4th pause respected anti-loop (message printed)
  [PASS] anti-loop: no new resume-scheduled.pid
================================
Results: 13 passed, 0 failed
All e2e tests passed.
```

### Passo 1 — ccusage disponível?

```
$ command -v ccusage
ccusage not in PATH (not globally installed)

$ npx -y ccusage --json | head -5
{
  "daily": [...],
  "totals": {...}
}
npx ccusage time: 15s  ← risco operacional (first-run download)
```

### Passo 2 — Probe standalone

```
$ rm -f logs/session-budget.json && bash bin/didio-budget-probe.sh
$ python3 -c "import json; d=json.load(open('logs/session-budget.json')); print(d.keys())"
dict_keys(['source', 'session_id', 'tokens_used', 'limit', 'pct', 'window_resets_at', 'weekly_resets_at', 'updated_at'])

Schema OK - all required fields present
source: ccusage   ← BUG: source=ccusage mas pct=0.0 (shape mismatch)
pct: 0.0          ← ESPERADO: pct real da sessão atual

$ npx ccusage --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.keys())"
dict_keys(['daily', 'totals'])   ← probe espera 'sessions' ou 'windows'

$ npx ccusage session --json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.keys())"
dict_keys(['sessions', 'totals'])   ← CORRETO para o probe
```

### Passo 3 — PostToolUse hook em agentes spawnados (análise de código)

```
spawn-agent.sh:131  export DIDIO_PROJECT_ROOT="$PROJECT_ROOT"
                    ↓ (antes de chamar claude -p)

.claude/settings.json PostToolUse:
  command: "bash $CLAUDE_PROJECT_DIR/bin/hooks/didio-post-tool.sh"
  ← CLAUDE_PROJECT_DIR setado pelo Claude CLI runtime (pwd do projeto)

didio-post-tool.sh:17:
  PROJECT="${DIDIO_PROJECT_ROOT:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  ← DIDIO_PROJECT_ROOT herdado do ambiente do spawn-agent ✓

Conclusão (código): hook DEVE disparar em subprocessos.
Runtime test omitido: risco de invocação claude aninhada.
```

### Passo 4 — PreToolUse deny com hard_pct forçado

```
# Config fixture: hard_pct=0.05, budget fixture: pct=0.50
$ DIDIO_PROJECT_ROOT=/tmp/fixture bash bin/hooks/didio-pre-tool.sh
stderr: {"hookSpecificOutput":{"hookEventName":"PreToolUse",
  "permissionDecision":"deny",
  "permissionDecisionReason":"Session budget at 50% >= hard threshold..."}}
exit code: 2  ← PASS

Nota: primeiro teste usou PROJECT_ROOT= (variável errada) → exit 0.
Correto é DIDIO_PROJECT_ROOT=. Hook re-deriva PROJECT de DIDIO_PROJECT_ROOT,
não de PROJECT_ROOT. Comportamento correto, protocolo de teste correto.
```

### Passo 5 — Scheduled resume

```
$ DIDIO_PAUSE_RESUME_OVERRIDE_SECS=999 bash bin/didio-budget-pause.sh ...
$ ls logs/resume-scheduled.pid
logs/resume-scheduled.pid  ← PASS

Mecanismo: nohup "sleep $SLEEP_SECS && didio-resume-feature.sh" &
(não usa CronCreate — usa sleep loop nohup)
```

### Passo 6 — Staleness guard

```
# Budget backdated -600s, pct=0.99
$ bash bin/hooks/didio-pre-tool.sh >/dev/null 2>&1; echo $?
0  ← PASS (stale → skip; pct=0.99 não causou deny)

STALE_MAX via config: session_guard.max_snapshot_age_secs (default 300s)
```

### Cleanup final

```
$ ls logs/*.json logs/.*.lock 2>/dev/null
(no matches — clean)  ← PASS
```
