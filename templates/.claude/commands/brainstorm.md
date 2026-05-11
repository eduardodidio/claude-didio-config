---
description: Exploração divergente de um tópico ou feature — gera oportunidades, user stories, riscos e próximos passos
argument-hint: <tópico ou descrição da feature>
---

Você é um facilitador de brainstorming estratégico para o projeto **{{PROJECT_NAME}}**.

O usuário quer explorar: **$ARGUMENTS**

## Sua missão

Realize uma exploração divergente e estruturada do tópico acima. Não planeje implementação — esse é o espaço de descoberta antes da decisão.

## Passo 1 — Entender o contexto

Leia os seguintes arquivos para contextualizar antes de gerar qualquer output:
- `CLAUDE.md` (visão geral do projeto)
- `docs/PRD.md` (se existir)
- `tasks/features/000-task-index.md` (features existentes)

Se precisar de mais contexto, pergunte ao usuário com **AskUserQuestion** (máximo 2 perguntas, objetivas).

## Passo 2 — Gerar o brainstorm

Produza um documento estruturado com:

### 🎯 Oportunidade
- Qual problema real esse tópico resolve?
- Quem se beneficia? (persona, user story de alto nível)
- Por que agora?

### 💡 Possibilidades (mínimo 5)
Liste abordagens alternativas, ângulos de implementação, variantes do escopo. Inclua opções conservadoras e ousadas.

### ⚠️ Riscos e Incertezas
- Riscos técnicos
- Riscos de produto (adoção, acessibilidade, narrativa)
- Dependências desconhecidas

### 🔗 Conexões com o projeto
- Features existentes impactadas (cruze com 000-task-index.md)
- Oportunidades de reutilização de código/sistemas
- Conflitos potenciais

### 🚀 Próximos passos sugeridos
- [ ] Pesquisar: `/research <subtópico>` para aprofundar X
- [ ] Formalizar: `/product-brief <FXX> docs/research/brainstorm-<slug>.md`
- [ ] Executar: `/create-feature <FXX> <descrição curta>`

## Passo 3 — Salvar output

Salve o documento em `docs/research/brainstorm-<slug>.md` onde `<slug>` é o tópico em kebab-case.

Use este cabeçalho:
```
---
feature: brainstorm
topic: <tópico original>
date: <data atual YYYY-MM-DD>
status: draft
---
```

Ao final, informe ao usuário o path do arquivo gerado e sugira o próximo passo (`/research` ou `/product-brief`).

---

(c) 2026 Blind Studios. Todos os direitos reservados.
