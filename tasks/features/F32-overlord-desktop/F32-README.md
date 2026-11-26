# F32 -- Overlord Desktop Assistant (Tauri)

**Status:** done
**Owner:** @operator
**PRD:** `docs/prd/F32-overlord-desktop.md`
**Depends on:** F30 (Kanban Board), F31 (War Room + Overlord agent core)

## Goal

Build a lightweight native desktop application using Tauri v2 that serves
as the Overlord's presence on the developer's machine. It launches at
startup, lives in the system tray, and provides a mini GUI for board
management, Overlord chat, blockage alerts, and OS notifications.

This is a NEW application (`overlord-desktop/`) alongside the existing
`dashboard/`. It reuses React components and shadcn/ui but has its own
Tauri build target and Rust backend.

## Technology Stack

- **Desktop shell:** Tauri v2 (~10MB, Rust backend, native OS integration)
- **Frontend:** React 18 + TypeScript + Vite + shadcn/ui (reuse from dashboard)
- **Backend commands:** Rust functions that shell out to `didio` CLI
- **Plugins:** tauri-plugin-autostart, tauri-plugin-notification, tauri-plugin-fs

## Architecture Impact

### New directory (entire application)
```
overlord-desktop/
  src-tauri/
    src/
      main.rs              -- app entry, tray setup, auto-launch
      commands.rs           -- Tauri commands (triage, promote, chat, etc.)
      watcher.rs            -- file watcher for boards + flags
      notifications.rs      -- OS notification bridge
    Cargo.toml
    tauri.conf.json
    icons/                  -- app icons (all sizes)
  src/
    App.tsx                 -- main window layout (tabs)
    main.tsx                -- React entry point
    views/
      Chat.tsx              -- Overlord chat channel
      BoardMini.tsx         -- compact board overview
      Alerts.tsx            -- blockage alerts panel
      Settings.tsx          -- avatar, silent mode, preferences
    components/
      Avatar.tsx            -- customizable avatar display
      AlertBanner.tsx       -- red/green status banner
      ChatMessage.tsx       -- single chat message bubble
      ChatInput.tsx         -- message input with send button
      ActionSuggestion.tsx  -- inline action button from Overlord
    hooks/
      useOverlordChat.ts   -- chat message state + Tauri invoke
      useBoardState.ts     -- board state via Tauri file watcher
      useAlerts.ts         -- alert state from flags
      useSettings.ts       -- settings persistence
    lib/
      types.ts             -- F32-specific TypeScript types
      tauriBridge.ts       -- typed wrappers around Tauri invoke/listen
  package.json
  tsconfig.json
  vite.config.ts
  tailwind.config.ts
  postcss.config.js
  index.html
  README.md
```

### Modified files
- `didio.config.json` -- add `overlord` config section
- `install.sh` -- add machine scan for parallelism + Overlord setup prompt
- `README.md` -- document F32 delivery

### New directories
- `logs/overlord/` -- chat history JSONL files
- `~/.claude-didio-config/overlord/` -- user-local avatar + preferences

## Wave Manifest

### Wave 0 -- Scaffold + Config + Machine Scan (all parallel, no dependencies)
| Task | Description | Status |
|------|-------------|--------|
| F32-T01 | Tauri v2 project scaffold (blackhawk-desktop/) | done |
| F32-T02 | Black Hawk config schema extension in didio.config.json | done |
| F32-T03 | Machine scan script for parallelism detection | done |
| F32-T04 | F32 TypeScript types + Tauri bridge utilities | done |

### Wave 1A -- Rust Backend (parallel, depend on T01)
| Task | Description | Status |
|------|-------------|--------|
| F32-T05 | Tauri commands: triage, promote, chat CLI bridge | done |
| F32-T06 | File watcher: boards, flags, chat log monitoring | done |
| F32-T07 | Notification bridge: OS notifications + tray icon state | done |

### Wave 1B -- Frontend Views (parallel, depend on T01 + T04)
| Task | Description | Status |
|------|-------------|--------|
| F32-T08 | Chat view + ChatMessage + ChatInput + ActionSuggestion | done |
| F32-T09 | BoardMini view: compact board overview | done |
| F32-T10 | Alerts view + AlertBanner component | done |

### Wave 2 -- Integration Features (depend on Wave 1A + 1B)
| Task | Description | Status |
|------|-------------|--------|
| F32-T11 | Settings view + Avatar component + silent mode toggle | done |
| F32-T12 | Auto-launch + chat persistence + install flow update | done |

### Wave 3 -- Tests + Docs (depend on all prior waves)
| Task | Description | Status |
|------|-------------|--------|
| F32-T13 | Integration tests + component tests (18 passing) | done |
| F32-T14 | Diagrams, ADR, README update, documentation | done |

## Dependency Graph

```
T01, T02, T03, T04 (Wave 0 -- all parallel)
 |
 +---> T05, T06, T07 (Wave 1A -- parallel, depend on T01)
 +---> T08, T09, T10 (Wave 1B -- parallel, depend on T01 + T04)
 |
 All Wave 1A + 1B ---> T11, T12 (Wave 2 -- parallel with each other)
 |
 All Wave 2 ---> T13, T14 (Wave 3 -- parallel with each other)
```

## Acceptance Criteria (feature-level)

- [ ] `overlord-desktop/` builds with `npm run tauri build` (or `cargo tauri build`)
- [ ] App launches, shows system tray icon, opens mini window
- [ ] Chat view: operator sends message, Overlord responds via CLI bridge
- [ ] Chat history persisted in `logs/overlord/chat-<date>.jsonl`
- [ ] BoardMini shows compact board state from F30 data files
- [ ] Red alert: tray icon turns red on critical flag, OS notification fires
- [ ] Green signal: tray icon returns to normal when resolved
- [ ] Silent mode: suppresses notifications but logs continue
- [ ] Avatar: configurable via Settings, displayed in chat + tray tooltip
- [ ] Auto-launch: configurable, uses tauri-plugin-autostart
- [ ] Machine scan: `install.sh` detects cores/RAM, suggests max_parallel
- [ ] `didio.config.json` includes `overlord` section with all config keys
- [ ] `npm run test` passes in overlord-desktop/
- [ ] Cross-platform: builds on Windows, macOS, Linux
