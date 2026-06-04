#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod config;
mod hapublish;
mod mqtt;
mod orchestrator;
mod protocol;
mod provider;
mod registry;

use orchestrator::Orchestrator;
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager, WebviewUrl, WebviewWindowBuilder,
};
use tauri_plugin_positioner::{Position, WindowExt};

fn lowest_battery(snap: &orchestrator::Snapshot) -> Option<i64> {
    snap.devices
        .iter()
        .filter_map(|d| d.values.get("battery").and_then(|v| v.as_i64()))
        .min()
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_positioner::init())
        .invoke_handler(tauri::generate_handler![
            commands::get_snapshot,
            commands::load_settings,
            commands::save_settings,
            commands::test_connection,
            commands::quit,
        ])
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let tray_handle = app.handle().clone();
            let orch = Orchestrator::new(move |snap| {
                let _ = tray_handle.emit("snapshot", &snap);
                if let Some(tray) = tray_handle.tray_by_id("main") {
                    let title = lowest_battery(&snap)
                        .map(|b| format!(" {}%", b))
                        .unwrap_or_default();
                    let _ = tray.set_title(Some(&title));
                }
            });
            app.manage(orch.clone());

            let popover = WebviewWindowBuilder::new(
                app,
                "popover",
                WebviewUrl::App("index.html".into()),
            )
            .title("Open Devices Bridge")
            .decorations(false)
            .always_on_top(true)
            .visible(false)
            .skip_taskbar(true)
            .inner_size(320.0, 420.0)
            .build()?;
            let _ = popover.hide();

            let settings_item =
                MenuItem::with_id(app, "settings", "Configurações…", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Sair", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&settings_item, &quit_item])?;

            let _tray = TrayIconBuilder::with_id("main")
                .icon(app.default_window_icon().unwrap().clone())
                .icon_as_template(true)
                .menu(&menu)
                // Deprecated `menu_on_left_click` replaced by `show_menu_on_left_click` (since 2.2.0)
                .show_menu_on_left_click(false)
                .on_menu_event(move |app, event| match event.id.as_ref() {
                    "settings" => open_settings(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
                    // TrayIconEvent::Click has `button` and `button_state` fields;
                    // only toggle popover on left-button click.
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(win) = app.get_webview_window("popover") {
                            if win.is_visible().unwrap_or(false) {
                                let _ = win.hide();
                            } else {
                                let _ = win.move_window(Position::TrayCenter);
                                let _ = win.show();
                                let _ = win.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            let settings = config::load();
            let password = config::password();
            orch.connect_mqtt(&settings, &password);
            orch.start(orchestrator::provider_roots());

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error building tauri app")
        .run(|_app, _event| {});
}

fn open_settings(app: &tauri::AppHandle) {
    if let Some(win) = app.get_webview_window("settings") {
        let _ = win.show();
        let _ = win.set_focus();
        return;
    }
    let _ = WebviewWindowBuilder::new(
        app,
        "settings",
        WebviewUrl::App("index.html?settings".into()),
    )
    .title("Open Devices Bridge — Configurações")
    .inner_size(440.0, 380.0)
    .resizable(false)
    .build();
}
