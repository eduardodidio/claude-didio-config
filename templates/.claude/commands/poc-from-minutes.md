---
description: Generate a runnable Vite+React POC from meeting minutes
---

# /poc-from-minutes <path-da-ata>

You are orchestrating the **meeting-to-POC** pipeline. The user has
just finished a discovery meeting and wants a runnable Vite+React POC
scaffolded from the meeting minutes file at `$1`.

## Step 1 — Validate input

Check that `$1` is a non-empty file. If missing or empty, tell the
user and stop.

## Step 2 — Read first H1 for default name

Read the first `# H1` line of `$1` to derive a default kebab-case
slug. If no `# H1` exists, fallback default is `poc-<YYYYMMDD-HHMMSS>`.

## Step 3 — Ask for parameters

Use `AskUserQuestion` with these 3 questions in a single call:

1. **"Nome do POC?"** (single-select)
   - Default: `<derived-slug>` (Recommended)
   - "Outro" — usuário digita slug manualmente
2. **"Diretório destino?"** (single-select)
   - Default: `$HOME/Projects/<nome>` (Recommended)
   - "Outro" — usuário digita path
3. **"Projeto de referência de estilo?"** (single-select)
   - Default mellon (`/Users/eduardodidio/mellon-magic-maker`)
     (Recommended)
   - "Tema neutro" — sem `--style-ref`, usa defaults do template
   - "Outro" — usuário digita path

## Step 4 — Confirm and run

Show a 1-line summary:

> Vou rodar: didio poc-from-minutes "$1" --name <nome> --dest <dest>
> [--style-ref <ref>]
> Isso vai criar um projeto novo em <dest> e levar ~2-3 min.

Then execute via Bash:

```bash
bin/didio-poc-from-minutes.sh "$1" --name <nome> --dest <dest> \
  [--style-ref <ref>]
```

Stream stdout/stderr to the user.

## Step 5 — Report

If exit 0, print:

> POC criado em <dest>. Para abrir:
> ```
> cd <dest> && npm run dev
> ```
> Manifest gerado: `<dest>/_pipeline/manifest.json`
> Log do pipeline: `<dest>/_pipeline/log.jsonl`

If exit ≠ 0, read `<dest>/_pipeline/log.jsonl` (last line), print
the failing step's `msg`, and suggest:

- exit 4 (manifest inválido): "ata muito ambígua — reescreva
  mencionando explicitamente pelo menos 1 tela e 1 entidade, depois
  tente de novo."
- exit 5 (npm install): "rede instável ou conflito de versões. Tente
  manualmente: `cd <dest> && npm install`."
- exit 6 (smoke fail): "porta 5173 ocupada ou erro em runtime. Verifique
  `<dest>/_pipeline/log.jsonl` e `/tmp/poc-dev.log`."
- exit 7 (git fail): "git config faltando? Rode `git -C <dest> commit
  -m 'scaffold from meeting <slug>'` manualmente."

## Constraints

- **Não invocar o orchestrator de agentes** diretamente. O `meeting-parser`
  é invocado **internamente** pelo `bin/didio-poc-pipeline.py`, não por
  este command.
- Não modificar arquivos fora de `<dest>`.
- Se o usuário não tem `bin/didio-poc-from-minutes.sh` (framework não
  inicializado), erro claro: "rode primeiro `/install-claude-didio-framework`."
