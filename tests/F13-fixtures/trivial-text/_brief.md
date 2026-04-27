# FX3 — Trivial Text Update (fixture for F13 TEA smoke)

Brief para testar TEA em feature trivial sem domínio especial.

Feature: atualizar o button label de "Save" para "Save changes" em
todos os formulários do app. Mudança de i18n key `btn.save` para
`btn.save_changes` no arquivo de tradução. Nenhuma lógica nova;
apenas copy e i18n key.

Stack assumida: React + i18next, testes unitários em Vitest.
