# FX2 — Accessible UI (fixture for F13 TEA smoke)

Brief para testar TEA em domínio de acessibilidade.

Feature: construir componente de formulário de contato acessível.
Requisitos: WCAG 2.1 AA, contrast ratio ≥ 4.5:1 em todos os textos,
labels para screen reader, foco visível em todos os controles.
Validação com axe-core no CI.

Stack assumida: React + TypeScript + jest-axe, testes em Vitest.
