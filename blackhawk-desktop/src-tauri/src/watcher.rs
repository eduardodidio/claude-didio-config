use notify::{Config, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::PathBuf;
use std::sync::mpsc;
use std::thread;
use tauri::Emitter;

use crate::commands::{get_alerts, get_board_state};

/// Watched directories relative to project root
const WATCH_PATHS: &[&str] = &[
    "logs/flags",
    "logs/warroom",
    "logs/overlord",
    "tasks/features",
];

/// Start file watchers that emit events to the frontend when board, alert, or
/// chat data changes on disk.
pub fn start_watchers(app_handle: tauri::AppHandle, project_root: PathBuf) {
    let (tx, rx) = mpsc::channel::<notify::Result<Event>>();

    thread::spawn(move || {
        let mut watcher: RecommendedWatcher =
            match Watcher::new(tx, Config::default()) {
                Ok(w) => w,
                Err(e) => {
                    eprintln!("[blackhawk-watcher] Failed to create watcher: {}", e);
                    return;
                }
            };

        // Watch each directory (create if missing)
        for rel in WATCH_PATHS {
            let dir = project_root.join(rel);
            if !dir.exists() {
                let _ = std::fs::create_dir_all(&dir);
            }
            if dir.exists() {
                if let Err(e) = watcher.watch(&dir, RecursiveMode::Recursive) {
                    eprintln!("[blackhawk-watcher] Cannot watch {}: {}", dir.display(), e);
                }
            }
        }

        println!("[blackhawk-watcher] File watchers active");

        // Debounce: batch events within a 500ms window
        let mut last_board_emit = std::time::Instant::now();
        let mut last_alert_emit = std::time::Instant::now();
        let debounce = std::time::Duration::from_millis(500);

        for event_result in rx {
            let event = match event_result {
                Ok(e) => e,
                Err(_) => continue,
            };

            // Only react to creates, modifications, and removals
            match event.kind {
                EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_) => {}
                _ => continue,
            }

            let path_str = event
                .paths
                .first()
                .and_then(|p| p.to_str())
                .unwrap_or_default();

            let now = std::time::Instant::now();

            if path_str.contains("flags") || path_str.contains("warroom") {
                if now.duration_since(last_alert_emit) > debounce {
                    last_alert_emit = now;
                    emit_alert_update(&app_handle);
                }
            }

            if path_str.contains("features") || path_str.contains("warroom") {
                if now.duration_since(last_board_emit) > debounce {
                    last_board_emit = now;
                    emit_board_update(&app_handle);
                }
            }

            if path_str.contains("overlord") && path_str.contains("chat-") {
                // Chat file changed externally — notify frontend
                let _ = app_handle.emit("chat-external-update", ());
            }
        }

        println!("[blackhawk-watcher] Watcher thread exiting");
    });
}

fn emit_board_update(app: &tauri::AppHandle) {
    // Run get_board_state synchronously for the watcher thread
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build();
    if let Ok(rt) = rt {
        match rt.block_on(get_board_state()) {
            Ok(state) => {
                let _ = app.emit("board-update", serde_json::json!({ "state": state }));
            }
            Err(e) => eprintln!("[blackhawk-watcher] board update error: {}", e),
        }
    }
}

fn emit_alert_update(app: &tauri::AppHandle) {
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build();
    if let Ok(rt) = rt {
        match rt.block_on(get_alerts()) {
            Ok(alerts) => {
                let _ = app.emit("alert-update", serde_json::json!({ "alerts": alerts }));
            }
            Err(e) => eprintln!("[blackhawk-watcher] alert update error: {}", e),
        }
    }
}
