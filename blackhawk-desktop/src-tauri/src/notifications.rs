use std::sync::Mutex;
use tauri::Emitter;

/// Shared application state for cross-module access
pub struct AppState {
    pub app_handle: Mutex<Option<tauri::AppHandle>>,
    pub silent_mode: Mutex<bool>,
    pub chat_lock: Mutex<()>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            app_handle: Mutex::new(None),
            silent_mode: Mutex::new(false),
            chat_lock: Mutex::new(()),
        }
    }
}

/// Tray icon status enum
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TrayStatus {
    Nominal,
    Alert,
    Muted,
}

impl TrayStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            TrayStatus::Nominal => "nominal",
            TrayStatus::Alert => "alert",
            TrayStatus::Muted => "muted",
        }
    }
}

/// Send an OS notification if not in silent mode
pub fn send_notification(
    app: &tauri::AppHandle,
    state: &AppState,
    title: &str,
    body: &str,
) {
    let silent = *state.silent_mode.lock().unwrap();
    if silent {
        return;
    }

    // Use tauri-plugin-notification
    if let Err(e) = tauri_plugin_notification::NotificationExt::notification(app)
        .builder()
        .title(title)
        .body(body)
        .show()
    {
        eprintln!("[blackhawk-notify] Failed to send notification: {}", e);
    }
}

/// Update the tray icon tooltip and emit a tray-update event to the frontend
pub fn update_tray_state(
    app: &tauri::AppHandle,
    status: TrayStatus,
    alert_count: usize,
) {
    let tooltip = match status {
        TrayStatus::Nominal => "Black Hawk - All clear".to_string(),
        TrayStatus::Alert => format!("Black Hawk - {} active alert(s)", alert_count),
        TrayStatus::Muted => "Black Hawk - Silent mode".to_string(),
    };

    let _ = app.emit(
        "tray-update",
        serde_json::json!({
            "state": {
                "status": status.as_str(),
                "tooltip": tooltip,
                "alertCount": alert_count
            }
        }),
    );
}
