# Diagrams Index

All diagrams are [Mermaid](https://mermaid.js.org/) `.mmd` files.

## F01 — didio monitoring dashboard

| File | Owner task | What it shows |
|---|---|---|
| [F01-dashboard-architecture.mmd](F01-dashboard-architecture.mmd) | F01-T09 | Component tree: App → Router → MainLayout → {Sidebar, Outlet, Footer} → views |
| [F01-dashboard-data-flow.mmd](F01-dashboard-data-flow.mmd) | F01-T06 | `state.json` → `fetchState` → React Query → `useDidioState` → views |
| [F01-dashboard-routes.mmd](F01-dashboard-routes.mmd) | F01-T14 | Route map for `/`, `/features`, `/agents`, `/easter-eggs` |

## F02 — Features view refactoring

| File | Owner task | What it shows |
|---|---|---|
| [F02-architecture.mmd](F02-architecture.mmd) | F02-T04 | Module dependencies: `Features.tsx` → `statusStyles.ts`, `Progress`, `selectors.ts`, `useDidioState`; external deps `@radix-ui/react-progress`, `framer-motion` |
| [F02-journey.mmd](F02-journey.mmd) | F02-T04 | User journey through the Features view: open page → polling → derived state → cards, progress bars, status chips |

## F03 — Log watcher & state.json improvements

| File | Owner task | What it shows |
|---|---|---|
| [F03-architecture.mmd](F03-architecture.mmd) | F03-T01 | Component/data-flow: `didio-log-watcher.sh` internals — load agents, README mtime cache, compute_feature, no-op guard, atomic write to `state.json` |
| [F03-journey.mmd](F03-journey.mmd) | F03-T01 | Watcher tick lifecycle — from tick start through feature enumeration, README parsing, JSON hash check, and conditional state write |
