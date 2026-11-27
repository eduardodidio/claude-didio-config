# Feature F44 — Live Kanban Board (Standalone)

**Status:** planned
**Owner:** @operator

## Goal

Standalone HTML Kanban board served by `didio board` that reads live data
from the project's JSON files. Two alternatable views (War Room + Standard),
dark/light mode, clean Jira-like UX with card details, progress, and filters.

## Architecture

```
didio board [--port 8844] [--open]
  └── bin/didio-board-server.py    (Python HTTP server)
       ├── GET /                   → serves board.html (SPA)
       ├── GET /api/warroom        → reads logs/warroom/cards/*.json
       ├── GET /api/pipelines      → reads logs/agents/pipeline-*.state.json
       ├── GET /api/features       → reads tasks/features/*/README.md
       └── GET /api/squad          → reads latest squad/bravo/charlie/delta reports
```

**Why standalone?** The React dashboard (F30/F31) lives inside Tauri and needs
`npm install + cargo build`. This board is zero-dependency — Python 3 stdlib
HTTP server + single HTML file with vanilla JS. Opens in any browser.

**Design reference:** Existing React components in `dashboard/src/components/kanban/`
and `dashboard/src/components/warroom/` define the data shape and UX patterns.
F44 mirrors their UX in vanilla HTML/CSS/JS for portability.

## Waves

- **Wave 0**: F44-T01, F44-T02 (backend server + data API)
- **Wave 1**: F44-T03, F44-T04, F44-T05 (UI: board shell, war room view, standard view — parallel, distinct files)
- **Wave 2**: F44-T06, F44-T07 (light/dark mode + E2E tests)
- **Wave 3**: F44-T08 (CLI wiring + docs + diagrams)

## Dependency Graph

```
F44-T01 (Python server)──→ F44-T03 (board shell + theme)
F44-T02 (data API layer) ─→ F44-T04 (war room view)
         │                 └→ F44-T05 (standard view)
         └───────────────────→ F44-T06 (light/dark mode)
                               F44-T07 (E2E tests)
                               F44-T08 (CLI + docs)
```

## UX Requirements

### Layout
- Full viewport height, responsive
- Header: logo, board tabs (War Room / Standard), theme toggle, stats bar
- Body: horizontal scrollable columns (raias Kanban)
- Each column: header with title + count, scrollable card area
- Cards: ID, title, body preview, tags, priority badge, progress bar, timestamps
- Card click: slide-in detail panel from right (like Jira)

### War Room Columns
| Column | Color | Cards with status |
|--------|-------|-------------------|
| Incoming | neutral gray | incoming |
| Triaging | amber/yellow | triaging |
| Assessed | blue | needs_input |
| Promoted | green | promoted |
| Deferred | slate | deferred |
| Archived | dim gray | archived |

### Standard Board Columns
| Column | Color | Source |
|--------|-------|--------|
| Backlog | gray | deferred warroom cards + future roadmap |
| Planned | purple | pipeline state = planned |
| In Progress | yellow | pipeline state = running (wave-N) |
| Review | blue | pipeline state = techlead/qa |
| Done | green | pipeline state = done, exit_code=0 |
| Failed | red | pipeline state with exit_code != 0 |

### Card UX (Jira-inspired)
- **War Room card**: card_id badge, title (truncated), body preview (2 lines),
  source icon (operator/agent/external), priority badge, tags, Alpha assessment
  indicator (promote/defer/archive/needs_input), promoted_to link, relative time
- **Standard card**: feature ID (bold mono), title, progress bar (% based on
  stages_completed/total), current stage label, task count, commit hash if done,
  pipeline exit code if failed

### Theme
- **Dark mode** (default): GitHub dark palette (#0d1117, #161b22, #30363d)
- **Light mode**: Clean white/gray palette, high contrast text
- Toggle via button in header, persists to localStorage
- CSS variables for all colors, single class swap on `<html>`

### Interactions
- Auto-refresh every 10s (configurable via query param `?refresh=N`)
- Card click → detail panel slides from right with full card data
- Filter by tag, priority, or status (dropdown in stats bar)
- Column WIP limit indicators (optional visual cue)
- Empty state illustrations per column

### Performance
- Single HTML file, zero npm dependencies
- CSS grid/flexbox layout, no framework
- Vanilla JS fetch for API calls
- Server-Sent Events (SSE) for live updates (stretch goal)

## Global acceptance criteria

- [ ] `didio board` starts server and opens browser
- [ ] War Room view shows all cards from logs/warroom/cards/ in correct columns
- [ ] Standard Board shows all features with pipeline state in correct columns
- [ ] Dark/Light mode toggle works, persists to localStorage
- [ ] Card detail panel shows full card data on click
- [ ] Auto-refresh updates board every 10s
- [ ] Stats bar shows correct counts per column
- [ ] Mobile responsive (columns stack vertically)
- [ ] Zero external dependencies (Python stdlib + vanilla HTML/CSS/JS)
- [ ] E2E test validates board serves and renders correctly
