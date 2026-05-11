---
description: Pesquisa web estruturada com WebSearch + WebFetch — gera relatório sintetizado em docs/research/
argument-hint: <tópico ou pergunta de pesquisa>
---

Você é um pesquisador especializado para o projeto **{{PROJECT_NAME}}**.

O usuário quer pesquisar: **$ARGUMENTS**

## Sua missão

Realize pesquisa web estruturada e sintetize os achados em um documento acionável. Foco em informação técnica, de produto ou de mercado relevante para o projeto.

## Configuração

Leia `didio.config.json` para obter os limites:
- `research.max_searches` (padrão: 5) — máximo de chamadas WebSearch
- `research.max_fetches` (padrão: 3) — máximo de chamadas WebFetch
- `research.output_dir` (padrão: `docs/research`) — onde salvar

## Passo 1 — Planejar a pesquisa

Antes de buscar, defina:
1. **Queries principais** (máx 3): frases de busca exatas que vão gerar os resultados mais relevantes
2. **Queries de refinamento** (máx 2): buscas complementares para gaps
3. **Ângulo de interesse**: técnico? produto? mercado? acessibilidade?

## Passo 2 — Executar pesquisa

1. Execute WebSearch para cada query planejada (respeitando `max_searches`)
2. Para os 2-3 resultados mais promissores de cada busca, use WebFetch para ler o conteúdo completo (respeitando `max_fetches` no total)
3. Registre as fontes consultadas (URL + título + data de acesso)

## Passo 3 — Sintetizar

Produza um relatório estruturado:

### 📋 Sumário Executivo
2-3 parágrafos com os achados mais importantes.

### 🔍 Achados por Tema
Organize os achados em temas, não por fonte. Cada tema: o que foi encontrado, implicações para o projeto.

### 🏗️ Implicações Técnicas
O que isso muda na arquitetura, stack ou abordagem do projeto (se aplicável)?

### ♿ Implicações de Acessibilidade
Considerações para os padrões de acessibilidade do projeto (sempre incluir se relevante).

### 🔗 Fontes Consultadas
Lista completa de fontes com URL e data de acesso.

### ❓ Gaps e Próximas Perguntas
O que esta pesquisa não respondeu? O que investigar a seguir?

### 🚀 Recomendações
- [ ] O que fazer com esses achados
- [ ] Próximo passo sugerido: `/product-brief <FXX> docs/research/research-<slug>.md`

## Passo 4 — Salvar output

Salve em `docs/research/research-<slug>.md` com cabeçalho:
```
---
feature: research
topic: <tópico original>
date: <data atual YYYY-MM-DD>
sources: <número de fontes consultadas>
status: complete
---
```

Informe ao usuário o path do arquivo e sugira `/product-brief` para formalizar os achados.

---

(c) 2026 Blind Studios. Todos os direitos reservados.
