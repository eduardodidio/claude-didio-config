# Black Hawk Desktop

Tauri v2 companion app for **claude-didio-config**. Provides a lightweight desktop
interface for interacting with agents, monitoring the Kanban board, and receiving
native OS notifications.

## Prerequisites

- **Node.js** >= 18
- **Rust** toolchain (rustup) with stable channel
- **Tauri v2 CLI** (installed via `npm install` as a dev dependency)
- Platform-specific dependencies:
  - **Windows**: WebView2 (included in Windows 10/11)
  - **macOS**: Xcode Command Line Tools
  - **Linux**: `webkit2gtk-4.1`, `libappindicator3-dev`, `librsvg2-dev`

## Getting Started

```bash
# Install frontend dependencies
npm install

# Run in development mode (launches Tauri + Vite dev server)
npm run tauri dev

# Build for production
npm run tauri build
```

## Project Structure

```
blackhawk-desktop/
  src/                  # React frontend (TypeScript + Tailwind)
    App.tsx             # Main app with tab layout
    main.tsx            # React entry point
    index.css           # Tailwind + Didio theme
    components/ui/      # Shared shadcn/ui primitives
    lib/utils.ts        # cn() utility
  src-tauri/            # Rust backend
    src/
      main.rs           # Tauri app setup, tray icon, window management
      lib.rs            # Module declarations
      commands.rs       # IPC command handlers (stub)
      watcher.rs        # File watcher for agent logs (stub)
      notifications.rs  # Native notification bridge (stub)
    Cargo.toml          # Rust dependencies
    tauri.conf.json     # Tauri configuration
    capabilities/       # Tauri v2 permission capabilities
    icons/              # App icons
  package.json          # Node dependencies + scripts
  vite.config.ts        # Vite config (port 1420 for Tauri)
  tailwind.config.ts    # Tailwind with Didio theme
  tsconfig.json         # TypeScript configuration
```

## Features (Planned)

- **Chat Tab** (F32-T03): Send messages to agents via CLI bridge
- **Board Tab** (F32-T04): Kanban board mirroring agent task state
- **Alerts Tab** (F32-T07): Native notifications for agent events
- **Settings Tab** (F32-T08): App configuration and preferences
- **System Tray** (F32-T01): Click to toggle window visibility
- **File Watcher** (F32-T06): Live updates from agent log files
