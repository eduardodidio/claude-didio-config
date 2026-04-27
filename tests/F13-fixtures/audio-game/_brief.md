# FX1 — Audio Maze (fixture for F13 TEA smoke)

Brief para testar TEA em domínio complexo (audio-only game).

Feature: implementar um mini-game de labirinto onde o usuário navega
por sons espacializados (sem visual). Perf budget: latency entre
input e som ≤ 50ms. Sem isso, jogabilidade quebra.

Stack assumida: web audio API + Howler.js, testes em Vitest.
