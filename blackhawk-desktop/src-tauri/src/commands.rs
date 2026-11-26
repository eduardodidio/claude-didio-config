use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use tauri::{Emitter, State};

use crate::notifications::AppState;

// ---- Rust equivalents of TypeScript types ----

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatAction {
    pub label: String,
    pub command: String,
    pub confirmed: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub id: String,
    pub role: String, // "operator" | "alpha"
    pub content: String,
    pub actions: Vec<ChatAction>,
    pub timestamp: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoardCard {
    pub feature: String,
    pub column: String,
    #[serde(default)]
    pub progress: u32,
    #[serde(default, rename = "taskTotal")]
    pub task_total: u32,
    #[serde(default, rename = "taskDone")]
    pub task_done: u32,
    #[serde(default, rename = "hasBlockage")]
    pub has_blockage: bool,
    #[serde(default, rename = "currentPhase")]
    pub current_phase: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoardState {
    pub cards: Vec<BoardCard>,
    #[serde(rename = "lastUpdated")]
    pub last_updated: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Alert {
    pub id: String,
    pub feature: String,
    pub task: Option<String>,
    pub severity: String,
    pub status: String,
    pub message: String,
    pub created_at: String,
    pub resolved_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BlackHawkSettings {
    #[serde(default, rename = "silentMode")]
    pub silent_mode: bool,
    #[serde(default, rename = "autoLaunch")]
    pub auto_launch: bool,
    #[serde(default = "default_true", rename = "notificationSound")]
    pub notification_sound: bool,
    #[serde(default, rename = "avatarPath")]
    pub avatar_path: String,
    #[serde(default = "default_chat_days", rename = "chatHistoryDays")]
    pub chat_history_days: u32,
    #[serde(default = "default_triage_interval", rename = "triageIntervalMinutes")]
    pub triage_interval_minutes: u32,
    #[serde(default = "default_width", rename = "desktopWidth")]
    pub desktop_width: u32,
    #[serde(default = "default_height", rename = "desktopHeight")]
    pub desktop_height: u32,
    #[serde(default = "default_position", rename = "desktopPosition")]
    pub desktop_position: String,
}

fn default_true() -> bool { true }
fn default_chat_days() -> u32 { 30 }
fn default_triage_interval() -> u32 { 15 }
fn default_width() -> u32 { 400 }
fn default_height() -> u32 { 600 }
fn default_position() -> String { "bottom-right".into() }

impl Default for BlackHawkSettings {
    fn default() -> Self {
        Self {
            silent_mode: false,
            auto_launch: false,
            notification_sound: true,
            avatar_path: String::new(),
            chat_history_days: 30,
            triage_interval_minutes: 15,
            desktop_width: 400,
            desktop_height: 600,
            desktop_position: "bottom-right".into(),
        }
    }
}

// ---- Path helpers ----

fn project_root() -> PathBuf {
    // Check DIDIO_PROJECT_ROOT env, then try common locations
    if let Ok(root) = std::env::var("DIDIO_PROJECT_ROOT") {
        return PathBuf::from(root);
    }
    // Fallback: walk up from executable to find didio.config.json
    if let Ok(exe) = std::env::current_exe() {
        let mut dir = exe.parent().map(|p| p.to_path_buf());
        while let Some(d) = dir {
            if d.join("didio.config.json").exists() {
                return d;
            }
            dir = d.parent().map(|p| p.to_path_buf());
        }
    }
    // Last resort: current directory
    std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
}

fn chat_log_dir() -> PathBuf {
    project_root().join("logs").join("overlord")
}

fn chat_log_path(date: &str) -> PathBuf {
    chat_log_dir().join(format!("chat-{}.jsonl", date))
}

fn settings_path() -> PathBuf {
    let home = dirs_or_home();
    home.join(".claude-didio-config").join("blackhawk").join("settings.json")
}

fn dirs_or_home() -> PathBuf {
    std::env::var("HOME")
        .or_else(|_| std::env::var("USERPROFILE"))
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("."))
}

fn today_str() -> String {
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    // Simple UTC date calculation
    let days = now / 86400;
    let y = (days * 4 + 2) / 1461 + 1970 - ((days * 4 + 2) % 1461 < 366) as u64;
    // Use chrono-free approach: format via system command on the platform
    // For simplicity, shell out to date
    let output = Command::new("date").arg("+%Y-%m-%d").output();
    match output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        Err(_) => format!("{}", y), // fallback
    }
}

fn now_iso() -> String {
    let output = Command::new("date").arg("-u").arg("+%Y-%m-%dT%H:%M:%SZ").output();
    match output {
        Ok(o) => String::from_utf8_lossy(&o.stdout).trim().to_string(),
        Err(_) => "1970-01-01T00:00:00Z".into(),
    }
}

fn new_uuid() -> String {
    // Simple UUID v4 without external crate
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    use std::time::{SystemTime, UNIX_EPOCH};

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();

    let mut hasher = DefaultHasher::new();
    nanos.hash(&mut hasher);
    std::thread::current().id().hash(&mut hasher);
    let h1 = hasher.finish();

    let mut hasher2 = DefaultHasher::new();
    (nanos + 1).hash(&mut hasher2);
    let h2 = hasher2.finish();

    format!(
        "{:08x}-{:04x}-4{:03x}-{:04x}-{:012x}",
        (h1 >> 32) as u32,
        (h1 >> 16) as u16 & 0xffff,
        h1 as u16 & 0x0fff,
        (h2 >> 48) as u16 & 0x3fff | 0x8000,
        h2 & 0xffffffffffff
    )
}

// ---- Shell helpers ----

fn run_didio(args: &[&str]) -> Result<String, String> {
    let root = project_root();
    let script = root.join("bin").join(format!("didio-blackhawk-{}.sh", args[0]));

    let result = if script.exists() {
        Command::new("bash")
            .arg(script.to_str().unwrap_or_default())
            .args(&args[1..])
            .env("DIDIO_PROJECT_ROOT", root.to_str().unwrap_or_default())
            .output()
    } else {
        // Try didio blackhawk <subcommand>
        let didio_bin = root.join("bin").join("didio-blackhawk.sh");
        Command::new("bash")
            .arg(didio_bin.to_str().unwrap_or_default())
            .args(args)
            .env("DIDIO_PROJECT_ROOT", root.to_str().unwrap_or_default())
            .output()
    };

    match result {
        Ok(output) => {
            if output.status.success() {
                Ok(String::from_utf8_lossy(&output.stdout).to_string())
            } else {
                let stderr = String::from_utf8_lossy(&output.stderr);
                Err(format!("Command failed: {}", stderr))
            }
        }
        Err(e) => Err(format!("Failed to execute command: {}", e)),
    }
}

// ---- Tauri commands ----

#[tauri::command]
pub async fn send_chat(message: String, state: State<'_, AppState>) -> Result<ChatMessage, String> {
    let today = today_str();
    let log_dir = chat_log_dir();
    fs::create_dir_all(&log_dir).map_err(|e| e.to_string())?;

    // Save operator message
    let operator_msg = ChatMessage {
        id: new_uuid(),
        role: "operator".into(),
        content: message.clone(),
        actions: vec![],
        timestamp: now_iso(),
    };
    append_chat_message(&today, &operator_msg)?;

    // Generate Alpha response
    let (content, actions) = generate_alpha_response(&message);

    let alpha_msg = ChatMessage {
        id: new_uuid(),
        role: "alpha".into(),
        content,
        actions,
        timestamp: now_iso(),
    };
    append_chat_message(&today, &alpha_msg)?;

    // Emit chat event
    if let Some(window) = state.app_handle.lock().unwrap().as_ref() {
        let _ = window.emit("chat-response", &alpha_msg);
    }

    Ok(alpha_msg)
}

fn generate_alpha_response(message: &str) -> (String, Vec<ChatAction>) {
    let lower = message.to_lowercase();

    // Detect commands / intent
    if lower.contains("triage") {
        return (
            "Roger. Ready to run triage on incoming War Room cards.".into(),
            vec![ChatAction {
                label: "Run Triage".into(),
                command: "didio blackhawk triage".into(),
                confirmed: false,
            }],
        );
    }

    if lower.contains("promote") {
        // Try to extract card ID
        let parts: Vec<&str> = message.split_whitespace().collect();
        let card_id = parts.iter()
            .find(|p| p.starts_with("WR-"))
            .unwrap_or(&"<card-id>");
        return (
            format!("Promoting card {} to Standard Board.", card_id),
            vec![ChatAction {
                label: "Confirm Promote".into(),
                command: format!("didio blackhawk promote {}", card_id),
                confirmed: false,
            }],
        );
    }

    if lower.contains("defer") {
        let parts: Vec<&str> = message.split_whitespace().collect();
        let card_id = parts.iter()
            .find(|p| p.starts_with("WR-"))
            .unwrap_or(&"<card-id>");
        return (
            format!("Deferring card {}.", card_id),
            vec![ChatAction {
                label: "Confirm Defer".into(),
                command: format!("didio blackhawk defer {}", card_id),
                confirmed: false,
            }],
        );
    }

    if lower.contains("status") || lower.contains("board") {
        return (
            "Board state loaded. Check the Board tab for current status.".into(),
            vec![ChatAction {
                label: "Refresh Board".into(),
                command: "refresh-board".into(),
                confirmed: false,
            }],
        );
    }

    if lower.contains("silent") {
        let enable = lower.contains("on") || lower.contains("enable");
        return (
            format!(
                "Silent mode {}. Notifications will be {}.",
                if enable { "enabled" } else { "disabled" },
                if enable { "suppressed" } else { "active" }
            ),
            vec![ChatAction {
                label: if enable { "Enable Silent" } else { "Disable Silent" }.into(),
                command: format!("set-silent-mode {}", enable),
                confirmed: false,
            }],
        );
    }

    // Default response
    (
        "Copy. Standing by for orders. Use 'triage', 'promote <card-id>', \
         'defer <card-id>', 'status', or 'silent on/off'."
            .into(),
        vec![],
    )
}

fn append_chat_message(date: &str, msg: &ChatMessage) -> Result<(), String> {
    let path = chat_log_path(date);
    let log_dir = path.parent().unwrap();
    fs::create_dir_all(log_dir).map_err(|e| e.to_string())?;

    let json = serde_json::to_string(msg).map_err(|e| e.to_string())?;
    use std::io::Write;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .map_err(|e| e.to_string())?;
    writeln!(file, "{}", json).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn run_triage() -> Result<String, String> {
    run_didio(&["triage"])
}

#[tauri::command]
pub async fn promote_card(card_id: String) -> Result<String, String> {
    run_didio(&["promote", &card_id])
}

#[tauri::command]
pub async fn execute_action(command: String) -> Result<String, String> {
    let root = project_root();
    let result = Command::new("bash")
        .arg("-c")
        .arg(&command)
        .env("DIDIO_PROJECT_ROOT", root.to_str().unwrap_or_default())
        .output()
        .map_err(|e| format!("Failed to execute: {}", e))?;

    if result.status.success() {
        Ok(String::from_utf8_lossy(&result.stdout).to_string())
    } else {
        Err(String::from_utf8_lossy(&result.stderr).to_string())
    }
}

#[tauri::command]
pub async fn get_board_state() -> Result<BoardState, String> {
    let root = project_root();
    let features_dir = root.join("tasks").join("features");

    let mut cards = Vec::new();

    if features_dir.exists() {
        let entries = fs::read_dir(&features_dir).map_err(|e| e.to_string())?;
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() { continue; }

            let dir_name = path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or_default()
                .to_string();

            // Look for status file or README
            let status_file = path.join("status.json");
            let readme = path.join(format!("{}-README.md", dir_name.split('-').next().unwrap_or(&dir_name)));

            let (column, progress, task_total, task_done, has_blockage, current_phase) =
                if status_file.exists() {
                    parse_status_file(&status_file)
                } else if readme.exists() || path.join(format!("{}-README.md", &dir_name.split('-').next().unwrap_or(""))).exists() {
                    // Infer from README status line
                    ("BACKLOG".into(), 0u32, 0u32, 0u32, false, None)
                } else {
                    continue;
                };

            cards.push(BoardCard {
                feature: dir_name,
                column,
                progress,
                task_total,
                task_done,
                has_blockage,
                current_phase,
            });
        }
    }

    Ok(BoardState {
        cards,
        last_updated: now_iso(),
    })
}

fn parse_status_file(path: &PathBuf) -> (String, u32, u32, u32, bool, Option<String>) {
    let content = fs::read_to_string(path).unwrap_or_default();
    let parsed: serde_json::Value = serde_json::from_str(&content).unwrap_or_default();

    let column = parsed["column"].as_str().unwrap_or("BACKLOG").to_string();
    let progress = parsed["progress"].as_u64().unwrap_or(0) as u32;
    let task_total = parsed["taskTotal"].as_u64().unwrap_or(0) as u32;
    let task_done = parsed["taskDone"].as_u64().unwrap_or(0) as u32;
    let has_blockage = parsed["hasBlockage"].as_bool().unwrap_or(false);
    let current_phase = parsed["currentPhase"].as_str().map(|s| s.to_string());

    (column, progress, task_total, task_done, has_blockage, current_phase)
}

#[tauri::command]
pub async fn get_alerts() -> Result<Vec<Alert>, String> {
    let root = project_root();
    let flags_dir = root.join("logs").join("flags");

    let mut alerts = Vec::new();

    if flags_dir.exists() {
        let entries = fs::read_dir(&flags_dir).map_err(|e| e.to_string())?;
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }

            let content = fs::read_to_string(&path).unwrap_or_default();
            let parsed: serde_json::Value = serde_json::from_str(&content).unwrap_or_default();

            let severity = match parsed["severity"].as_str().unwrap_or("info") {
                "critical" | "error" => "critical",
                "warning" | "warn" => "warning",
                _ => "info",
            };

            let status = if parsed["resolved"].as_bool().unwrap_or(false) {
                "resolved"
            } else {
                "active"
            };

            alerts.push(Alert {
                id: parsed["id"].as_str().unwrap_or_default().to_string(),
                feature: parsed["feature"].as_str().unwrap_or_default().to_string(),
                task: parsed["task"].as_str().map(|s| s.to_string()),
                severity: severity.to_string(),
                status: status.to_string(),
                message: parsed["message"].as_str().unwrap_or_default().to_string(),
                created_at: parsed["created_at"].as_str().unwrap_or_default().to_string(),
                resolved_at: parsed["resolved_at"].as_str().map(|s| s.to_string()),
            });
        }
    }

    // Sort: active first, then by created_at descending
    alerts.sort_by(|a, b| {
        let status_ord = if a.status == "active" && b.status != "active" {
            std::cmp::Ordering::Less
        } else if a.status != "active" && b.status == "active" {
            std::cmp::Ordering::Greater
        } else {
            std::cmp::Ordering::Equal
        };
        status_ord.then_with(|| b.created_at.cmp(&a.created_at))
    });

    Ok(alerts)
}

#[tauri::command]
pub async fn get_settings() -> Result<BlackHawkSettings, String> {
    let path = settings_path();
    if path.exists() {
        let content = fs::read_to_string(&path).map_err(|e| e.to_string())?;
        serde_json::from_str(&content).map_err(|e| e.to_string())
    } else {
        Ok(BlackHawkSettings::default())
    }
}

#[tauri::command]
pub async fn update_settings(settings: serde_json::Value) -> Result<(), String> {
    let path = settings_path();
    let parent = path.parent().unwrap();
    fs::create_dir_all(parent).map_err(|e| e.to_string())?;

    // Merge with existing settings
    let mut current = if path.exists() {
        let content = fs::read_to_string(&path).map_err(|e| e.to_string())?;
        serde_json::from_str::<serde_json::Value>(&content).unwrap_or_default()
    } else {
        serde_json::to_value(BlackHawkSettings::default()).unwrap_or_default()
    };

    if let (Some(current_obj), Some(new_obj)) = (current.as_object_mut(), settings.as_object()) {
        for (key, value) in new_obj {
            current_obj.insert(key.clone(), value.clone());
        }
    }

    let json = serde_json::to_string_pretty(&current).map_err(|e| e.to_string())?;
    fs::write(&path, json).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn get_chat_history(date: Option<String>) -> Result<Vec<ChatMessage>, String> {
    let d = date.unwrap_or_else(|| today_str());
    let path = chat_log_path(&d);

    if !path.exists() {
        return Ok(vec![]);
    }

    let content = fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let messages: Vec<ChatMessage> = content
        .lines()
        .filter(|l| !l.trim().is_empty())
        .filter_map(|l| serde_json::from_str(l).ok())
        .collect();

    Ok(messages)
}

#[tauri::command]
pub async fn set_silent_mode(enabled: bool, state: State<'_, AppState>) -> Result<(), String> {
    // Update settings file
    let settings_val = serde_json::json!({ "silentMode": enabled });
    update_settings(settings_val).await?;

    // Update in-memory state
    *state.silent_mode.lock().unwrap() = enabled;

    Ok(())
}
