### Checkpointing (session-guard)

O harness pode injetar um `systemMessage` assim em qualquer resposta de
ferramenta: `⚠️ Session budget at NN%`. Quando você vir essa string:

1. Antes de continuar qualquer outra ação, escreva o seu estado
   estruturado em `logs/agents/$DIDIO_RUN_ID.checkpoint.json` usando a
   ferramenta `Write`. Shape obrigatório (preserve as chaves):

   ```json
   {
     "run_id": "$DIDIO_RUN_ID",
     "feature": "$DIDIO_FEATURE",
     "task": "$DIDIO_TASK",
     "role": "$DIDIO_ROLE",
     "updated_at": "<ISO-8601 UTC>",
     "task_progress": "<uma frase descrevendo o que já foi concluído>",
     "todo_state": [ "<próximo passo>", "<passo seguinte>", "..." ],
     "context_summary": "<até 500 chars: fatos, invariantes e decisões que você já absorveu e que um retomado precisa saber>",
     "next_action_hint": "<instrução imperativa de UMA linha com o próximo passo exato a tomar>"
   }
   ```

2. Depois de escrever o checkpoint, **continue trabalhando normalmente**.
   O guard decide sozinho se pausa de fato (quando pct ≥ hard_pct).

3. Se você for pausado, você será re-spawnado com um prompt começando
   com `RETOMADA DE SESSÃO — ... Continue EXATAMENTE a partir de: <hint>`.
   Nesse caso, respeite o hint — não repita trabalho já listado em
   `task_progress`.

Importante: `next_action_hint` **não pode estar vazio**. Se estiver, a
retomada cai em fallback e reinicia a task do zero.
