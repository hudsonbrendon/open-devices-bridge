//! Tauri commands callable from the Svelte frontend.
use crate::config::{self, Settings};
use crate::mqtt;
use crate::orchestrator::{Orchestrator, Snapshot};
use std::sync::mpsc::channel;
use std::time::Duration;

#[tauri::command]
pub fn get_snapshot(orch: tauri::State<Orchestrator>) -> Snapshot {
    orch.snapshot()
}

#[tauri::command]
pub fn load_settings() -> Settings {
    config::load()
}

#[tauri::command]
pub fn save_settings(
    orch: tauri::State<Orchestrator>,
    settings: Settings,
    password: String,
) -> Result<(), String> {
    config::save(&settings).map_err(|e| e.to_string())?;
    config::set_password(&password);
    orch.connect_mqtt(&settings, &password);
    Ok(())
}

/// Try connecting to the broker; returns Ok(()) on success within a timeout.
#[tauri::command]
pub fn test_connection(settings: Settings, password: String) -> Result<(), String> {
    let (tx, rx) = channel();
    let handle = mqtt::connect(&settings, &password, move |status| {
        if status == mqtt::Status::Connected {
            let _ = tx.send(());
        }
    });
    if handle.is_none() {
        return Err("Host/porta inválidos".into());
    }
    match rx.recv_timeout(Duration::from_secs(8)) {
        Ok(()) => Ok(()),
        Err(_) => Err("Timeout — sem resposta do broker".into()),
    }
}

#[tauri::command]
pub fn quit(app: tauri::AppHandle) {
    app.exit(0);
}
