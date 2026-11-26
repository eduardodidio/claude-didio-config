// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager,
};

mod commands;
mod notifications;
mod watcher;

use notifications::AppState;

fn main() {
    let app_state = AppState::new();

    tauri::Builder::default()
        .manage(app_state)
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            Some(vec![]),
        ))
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_fs::init())
        .setup(|app| {
            // Store app handle in state for cross-module use
            let state = app.state::<AppState>();
            *state.app_handle.lock().unwrap() = Some(app.handle().clone());

            // Build the system tray menu
            let quit_i = MenuItem::with_id(app, "quit", "Quit Black Hawk", true, None::<&str>)?;
            let show_i = MenuItem::with_id(app, "show", "Show Window", true, None::<&str>)?;
            let silent_i = MenuItem::with_id(app, "silent", "Toggle Silent Mode", true, None::<&str>)?;
            let triage_i = MenuItem::with_id(app, "triage", "Run Triage", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &triage_i, &silent_i, &quit_i])?;

            // Build the tray icon
            let _tray = TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .menu(&menu)
                .menu_on_left_click(false)
                .tooltip("Black Hawk Desktop")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "quit" => {
                        app.exit(0);
                    }
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.set_focus();
                        }
                    }
                    "silent" => {
                        let state = app.state::<AppState>();
                        let mut silent = state.silent_mode.lock().unwrap();
                        *silent = !*silent;
                        let is_silent = *silent;
                        drop(silent);

                        let status = if is_silent {
                            notifications::TrayStatus::Muted
                        } else {
                            notifications::TrayStatus::Nominal
                        };
                        notifications::update_tray_state(app, status, 0);
                    }
                    "triage" => {
                        let app_clone = app.clone();
                        std::thread::spawn(move || {
                            let rt = tokio::runtime::Builder::new_current_thread()
                                .enable_all()
                                .build();
                            if let Ok(rt) = rt {
                                match rt.block_on(commands::run_triage()) {
                                    Ok(result) => {
                                        let state = app_clone.state::<AppState>();
                                        notifications::send_notification(
                                            &app_clone,
                                            &state,
                                            "Triage Complete",
                                            &result,
                                        );
                                    }
                                    Err(e) => {
                                        eprintln!("[blackhawk] Triage error: {}", e);
                                    }
                                }
                            }
                        });
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // Start file watchers
            let project_root = std::env::var("DIDIO_PROJECT_ROOT")
                .map(std::path::PathBuf::from)
                .unwrap_or_else(|_| std::env::current_dir().unwrap_or_default());
            watcher::start_watchers(app.handle().clone(), project_root);

            println!("[blackhawk] Tauri app started successfully");
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::send_chat,
            commands::run_triage,
            commands::promote_card,
            commands::execute_action,
            commands::get_board_state,
            commands::get_alerts,
            commands::get_settings,
            commands::update_settings,
            commands::get_chat_history,
            commands::set_silent_mode,
        ])
        .run(tauri::generate_context!())
        .expect("error while running Black Hawk Desktop");
}
