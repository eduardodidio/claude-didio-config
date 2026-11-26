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

    // Serialize CLI calls to prevent overlapping claude -p invocations
    let _lock = state.chat_lock.lock().unwrap();

    // Generate Alpha response via Claude CLI
    let (content, actions) = match call_claude_cli(&message) {
        Ok((c, a)) => (c, a),
        Err(e) => (format!("[Error] {}", e), vec![]),
    };

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

fn call_claude_cli(message: &str) -> Result<(String, Vec<ChatAction>), String> {
    let system_prompt = "You are Black Hawk Alpha, the primary tactical agent \
        for the didio orchestrator. You help operators manage features, triage \
        War Room cards, and monitor pipeline health. Available commands: triage, \
        promote <card-id>, defer <card-id>, status, silent on/off. When suggesting \
        an action, put it on its own line: [ACTION: <label>] <command>";

    let full_prompt = format!("{}\n\nOperator says: {}", system_prompt, message);

    let output = Command::new("claude")
        .arg("-p")
        .arg(&full_prompt)
        .output();

    match output {
        Ok(o) if o.status.success() => {
            let raw = String::from_utf8_lossy(&o.stdout).to_string();
            let (content, actions) = parse_alpha_output(&raw);
            Ok((content, actions))
        }
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            Err(format!("Claude CLI error: {}", stderr))
        }
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            Err("Claude CLI not found on PATH. Install: npm i -g @anthropic-ai/claude-code".into())
        }
        Err(e) => Err(format!("Failed to spawn Claude CLI: {}", e)),
    }
}

fn parse_alpha_output(raw: &str) -> (String, Vec<ChatAction>) {
    let mut content_lines = Vec::new();
    let mut actions = Vec::new();
    let action_prefix = "[ACTION: ";

    for line in raw.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with(action_prefix) {
            if let Some(end_bracket) = trimmed.find(']') {
                let label = trimmed[action_prefix.len()..end_bracket].to_string();
                let command = trimmed[end_bracket + 1..].trim().to_string();
                actions.push(ChatAction { label, command, confirmed: false });
            } else {
                content_lines.push(line.to_string());
            }
        } else {
            content_lines.push(line.to_string());
        }
    }

    (content_lines.join("\n").trim().to_string(), actions)
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

const ALL_STAGES: &[&str] = &[
    "handler_gate", "architect", "readiness", "tea",
    "waves", "techlead", "qa", "post_review",
];

fn stage_to_column(stage: &str) -> &'static str {
    match stage {
        "architect" | "readiness" | "tea" => "PLANNING",
        "waves" => "RUNNING",
        "techlead" | "qa" | "post_review" => "REVIEW",
        _ => "BACKLOG",
    }
}

fn pipeline_state_to_card(parsed: &serde_json::Value) -> Option<BoardCard> {
    let feature = parsed["feature"].as_str()?.to_string();
    let status = parsed["status"].as_str().unwrap_or("unknown");
    let stage = parsed["stage"].as_str().unwrap_or("");

    let stages_completed = parsed["stages_completed"].as_array()
        .map(|a| a.len() as u32).unwrap_or(0);
    let progress = ((stages_completed as f64 / ALL_STAGES.len() as f64) * 100.0) as u32;

    let (column, has_blockage) = match status {
        "completed" => ("DONE", false),
        "running" => (stage_to_column(stage), false),
        "failed" => (stage_to_column(stage), true),
        "paused" => (stage_to_column(stage), false),
        "cancelled" => ("BACKLOG", false),
        _ => ("BACKLOG", false),
    };

    Some(BoardCard {
        feature,
        column: column.to_string(),
        progress: if status == "completed" { 100 } else { progress },
        task_total: ALL_STAGES.len() as u32,
        task_done: stages_completed,
        has_blockage,
        current_phase: if stage.is_empty() { None } else { Some(stage.to_string()) },
    })
}

#[tauri::command]
pub async fn get_board_state() -> Result<BoardState, String> {
    let root = project_root();
    let agents_dir = root.join("logs").join("agents");
    let mut cards = Vec::new();

    if agents_dir.exists() {
        let entries = fs::read_dir(&agents_dir).map_err(|e| e.to_string())?;
        for entry in entries.flatten() {
            let path = entry.path();
            let fname = path.file_name()
                .and_then(|n| n.to_str())
                .unwrap_or_default();
            if !fname.starts_with("pipeline-") || !fname.ends_with(".state.json") {
                continue;
            }
            let content = fs::read_to_string(&path).unwrap_or_default();
            let parsed: serde_json::Value = serde_json::from_str(&content)
                .unwrap_or_default();
            if let Some(card) = pipeline_state_to_card(&parsed) {
                cards.push(card);
            }
        }
    }

    cards.sort_by_key(|c| match c.column.as_str() {
        "RUNNING" => 0, "REVIEW" => 1, "PLANNING" => 2,
        "BACKLOG" => 3, "DONE" => 4, _ => 5,
    });

    Ok(BoardState { cards, last_updated: now_iso() })
}

#[tauri::command]
pub async fn get_alerts() -> Result<Vec<Alert>, String> {
    let root = project_root();
    let flags_dir = root.join("logs").join("agents").join("flags");

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

            let id = parsed["flag_id"].as_str()
                .or_else(|| parsed["id"].as_str())
                .unwrap_or_default().to_string();

            let raw_type = parsed["type"].as_str()
                .or_else(|| parsed["severity"].as_str())
                .unwrap_or("info");
            let severity = match raw_type {
                "blocked" => "critical",
                "needs_review" | "warning" | "warn" => "warning",
                "critical" | "error" => "critical",
                _ => "info",
            };

            let created_at = parsed["raised_at"].as_str()
                .or_else(|| parsed["created_at"].as_str())
                .unwrap_or_default().to_string();

            let status = if parsed["resolved"].as_bool().unwrap_or(false) {
                "resolved"
            } else {
                "active"
            };

            alerts.push(Alert {
                id,
                feature: parsed["feature"].as_str().unwrap_or_default().to_string(),
                task: parsed["task"].as_str().map(|s| s.to_string()),
                severity: severity.to_string(),
                status: status.to_string(),
                message: parsed["message"].as_str().unwrap_or_default().to_string(),
                created_at,
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
