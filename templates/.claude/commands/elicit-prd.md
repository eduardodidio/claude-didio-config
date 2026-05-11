---
description: PRD elicitation interativa — 8 perguntas focadas, escreve draft em claude-didio-out/prd-drafts/
argument-hint: <FXX> "<título>"
---

# /elicit-prd — PRD elicitation interativa

Você é o orquestrador de um questionário de PRD para o framework
**claude-didio-config**. O usuário invocou `/elicit-prd $ARGUMENTS`
para criar um rascunho estruturado de PRD **antes** de rodar
`/plan-feature` (e portanto antes de qualquer Architect).

**Importante:** este command **não** spawna agente. Toda a interação
roda no seu próprio contexto. Use `AskUserQuestion` quando disponível
(fallback: prompt textual estruturado com as mesmas opções listadas).

---

## Step 1 — Validar input

Parsear `$ARGUMENTS`. Formato esperado: `<FXX> "<título>"`.

- Extrair `FXX` (primeiro token). Validar contra regex `^F[0-9]+$`.
  Se inválido, abortar com:
  `Uso: /elicit-prd F12 "título da feature" — FXX deve ser F seguido de dígitos.`
- Extrair `<título>` (resto dos argumentos, sem aspas externas).
  Se vazio, abortar com:
  `Título não pode ser vazio. Uso: /elicit-prd F12 "título da feature"`

---

## Step 2 — Carregar template de perguntas

Leia o arquivo `templates/docs/prd/elicit-questions.md`.

Se o arquivo não existir, abortar com:
`elicit-questions.md não encontrado — rode bin/didio-sync-project.sh ou verifique a instalação do framework.`

Após a leitura, parsear os blocos marcados como `## Q*` (perguntas
obrigatórias) e `## C*` (perguntas condicionais). Para cada bloco,
extrair os campos `id`, `prompt`, `target`, `required` e `trigger`
(onde aplicável). Você usará esses campos nos steps seguintes.
**Não invente perguntas** — use exclusivamente as do template.

---

## Step 3 — Verificar output

Garantir que o diretório `claude-didio-out/prd-drafts/` existe.
Se não existir, criar com `mkdir -p` via ferramenta Bash.

Caminho do draft: `claude-didio-out/prd-drafts/<FXX>-prd.md`
(substituir `<FXX>` pelo valor validado no Step 1).

Se o arquivo já existir, perguntar ao usuário via `AskUserQuestion`:
> "O arquivo `claude-didio-out/prd-drafts/<FXX>-prd.md` já existe.
> O que deseja fazer?"
> Opções: `overwrite` / `keep` (manter e sair) / `abort`

- `keep` → encerrar o command sem alterações.
- `abort` → encerrar o command sem alterações.
- `overwrite` → continuar.

---

## Step 4 — Conduzir entrevista

Para cada pergunta `Q*` (em ordem crescente de id), apresentar ao
usuário via `AskUserQuestion` com `kind: freeform` o campo `prompt`
extraído do template — **um prompt por turno, sem batch**.

- Se a resposta for o literal `skip` (case-insensitive;
  regex `^\s*skip\s*$`), registrar o valor especial `__SKIP__` para
  esse `id`. Não rejeitar semanticamente respostas curtas ou vagas.

Para cada bloco `## C*` (condicional), avaliar o campo `trigger`
contra as respostas já coletadas e/ou o `<título>` fornecido.
Disparar a pergunta condicional **somente se** o trigger for
satisfeito. Aplicar a mesma regra de `skip`.

---

## Step 5 — Compor draft

Montar o conteúdo markdown no formato definido em
`templates/docs/prd/template.md` (abrir o arquivo, copiar a
estrutura e preencher as seções com as respostas coletadas).
**Não** reproduzir a estrutura de `templates/docs/prd/template.md` inline aqui.

Mapeamento de respostas:
- Para cada `id` com valor `__SKIP__`, escrever literalmente
  `**Não respondido — preencher antes de planejar**` na seção
  correspondente do draft.
- Para `id` com resposta real, preencher a seção com o texto fornecido.

Inferir o campo de objetivo a partir das respostas de `problem` e
`success`. Se ambos forem `__SKIP__`, usar placeholder genérico.

---

## Step 6 — Escrever draft

Escrever o markdown composto em
`claude-didio-out/prd-drafts/<FXX>-prd.md` via ferramenta de escrita
de arquivo.

Exibir resumo ao usuário:
`✏️ Draft escrito em claude-didio-out/prd-drafts/<FXX>-prd.md (N puladas, M respondidas).`

---

## Step 7 — Perguntar cópia para brief

Via `AskUserQuestion`, perguntar:
> "Deseja copiar este draft para `tasks/features/<FXX>-*/_brief.md` agora?"
> Opções: `yes` / `no`

---

## Step 8 — Se sim, copiar para brief

Derivar `<slug>` a partir do `<título>`:
1. Converter para lowercase.
2. Substituir espaços por hífens.
3. Remover caracteres que não sejam `[a-z0-9-]` (strip non-ASCII,
   pontuação, etc.) — esse é o kebab-case ASCII da convenção do projeto.
4. Colapsar sequências de hífens em um único hífen.
5. Remover hífens iniciais/finais.

Exemplo: `"Minha Feature 2!"` → `minha-feature-2`.

Verificar se já existe algum diretório `tasks/features/<FXX>-*/`:
- Se sim: reutilizar o diretório existente (independente do slug),
  avisar o usuário: `⚠️ Diretório existente reutilizado: tasks/features/<FXX>-<slug-existente>/`
- Se não: criar `tasks/features/<FXX>-<slug>/` via `mkdir -p`.

Copiar o draft:
```
cp claude-didio-out/prd-drafts/<FXX>-prd.md tasks/features/<FXX>-<slug>/_brief.md
```

Confirmar: `✅ Brief escrito em tasks/features/<FXX>-<slug>/_brief.md`

---

## Step 9 — Hint final

Sempre (independente da escolha yes/no no Step 7), exibir:

```
🔁 Próximo passo: /plan-feature <FXX>
   O draft está preservado em claude-didio-out/prd-drafts/<FXX>-prd.md
   e pode ser editado manualmente antes de planejar.
```

---

## Tabela de erros

| Situação                                | Ação                                                     |
|-----------------------------------------|----------------------------------------------------------|
| FXX inválido (não bate `^F[0-9]+$`)     | exit 1 com mensagem de uso                               |
| Título vazio                            | exit 1 com mensagem de uso                               |
| `elicit-questions.md` ausente           | exit 1 com sugestão de sync                              |
| Draft já existe                         | AskUserQuestion: `overwrite` / `keep` / `abort`          |
| Feature dir já existe com slug diferente| Reutilizar dir existente, avisar usuário                 |
| `claude-didio-out/` inexistente         | Criar com `mkdir -p`                                     |

---

## Regras invioláveis

- **NÃO** lançar sub-agentes via CLI `didio` (subcomandos de spawn ou execução de Wave).
- **NÃO** invocar ferramentas `Task` ou `Agent` para sub-agentes.
- **NÃO** inventar perguntas além das definidas em `templates/docs/prd/elicit-questions.md`.
- **NÃO** duplicar a estrutura de seções de `templates/docs/prd/template.md` neste command.
- `skip` (case-insensitive) → sempre registrar como `__SKIP__`, nunca rejeitar.

