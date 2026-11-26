# Black Hawk Desktop Configuration

All keys live under the `blackhawk` section of `didio.config.json`.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | boolean | `true` | Whether the Black Hawk Alpha agent is active |
| `auto_triage` | boolean | `true` | Automatically triage new features on interval |
| `triage_interval_minutes` | integer | `30` | Minutes between automatic triage runs (5-1440) |
| `knowledge_sources` | string[] | `["adr", "learnings", "retrospectives"]` | Knowledge sources for Black Hawk Alpha context |
| `max_concurrent_promotions` | integer | `2` | Max features promoted concurrently (1-10) |
| `promotion_requires_confirmation` | boolean | `false` | Whether promotion needs user confirmation |
| `defer_auto_archive_days` | integer | `30` | Days before deferred features are auto-archived (1-365) |
| `auto_launch` | boolean | `true` | Launch Black Hawk Desktop at system startup |
| `silent_mode` | boolean | `false` | Suppress all notifications (logs still recorded) |
| `avatar_path` | string | `""` | Path to custom avatar image (PNG/SVG). Empty uses default |
| `notification_sound` | boolean | `true` | Play sound on notifications |
| `chat_history_days` | integer | `30` | Days to retain chat history before cleanup (1-365) |
| `desktop_app.width` | integer | `400` | Window width in pixels (300-1200) |
| `desktop_app.height` | integer | `600` | Window height in pixels (400-1600) |
| `desktop_app.position` | string | `"bottom-right"` | Window position: `bottom-right`, `bottom-left`, `top-right`, `top-left`, `center` |

## Shell Helpers

The following functions are available after sourcing `bin/didio-config-lib.sh`:

| Function | Returns | Default |
|----------|---------|---------|
| `didio_blackhawk_enabled` | `"true"` / `"false"` | `"true"` |
| `didio_blackhawk_auto_triage` | `"true"` / `"false"` | `"true"` |
| `didio_blackhawk_triage_interval` | integer (string) | `"30"` |
| `didio_blackhawk_max_promotions` | integer (string) | `"2"` |
| `didio_blackhawk_knowledge_sources` | JSON array | `'["adr","learnings","retrospectives"]'` |
| `didio_blackhawk_auto_launch` | `"true"` / `"false"` | `"true"` |
| `didio_blackhawk_silent_mode` | `"true"` / `"false"` | `"false"` |
| `didio_blackhawk_avatar_path` | string | `""` |
| `didio_blackhawk_chat_history_days` | integer (string) | `"30"` |

## JSON Schema

See `schemas/blackhawk-config.schema.json` for the full JSON Schema (draft-07)
that validates this section.
