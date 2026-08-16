mod commands;
mod models;
mod services;

use commands::*;
use services::*;
use std::sync::atomic::{AtomicBool, Ordering};
use tauri::menu::{MenuBuilder, MenuItemBuilder};
use tauri::tray::TrayIconBuilder;
use tauri::{Manager, WindowEvent};

struct ExitState(AtomicBool);

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }))
        .manage(AppState::new(SettingsService::new()))
        .manage(ExitState(AtomicBool::new(false)))
        .invoke_handler(tauri::generate_handler![
            app_bootstrap,
            env_detect,
            env_install_dsh,
            env_update_dsh,
            env_install_node,
            env_ensure_pnpm,
            web_start,
            web_stop,
            web_open_external,
            web_open_session,
            web_open_window,
            sessions_sync,
            sessions_toggle_pin,
            sessions_reveal,
            plugins_refresh,
            plugins_set_profile,
            plugins_install,
            plugins_update,
            plugins_remove,
            plugins_pick_zip,
            plugins_pick_folder,
            settings_update,
            settings_reset,
            logs_clear,
            logs_export,
            shell_open_external,
            shell_reveal,
            shell_open_path
        ])
        .setup(|app| {
            let handle = app.handle().clone();
            setup_tray(app)?;
            if std::env::var("DSH_SHELL_SMOKE").as_deref() == Ok("1") {
                initial_setup(&handle)?;
                rust_smoke(&handle);
            } else {
                std::thread::spawn(move || {
                    let _ = initial_setup(&handle);
                });
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                if window.label() == "main" {
                    let app = window.app_handle();
                    let should_hide = !app.state::<ExitState>().0.load(Ordering::SeqCst)
                        && !app
                            .state::<AppState>()
                            .settings
                            .lock()
                            .unwrap()
                            .data
                            .stop_when_closed;
                    if should_hide {
                        api.prevent_close();
                        let _ = window.hide();
                        return;
                    }
                }
            }
            if matches!(event, WindowEvent::Destroyed) && window.label() == "main" {
                let app = window.app_handle().clone();
                let state = app.state::<AppState>();
                if state.settings.lock().unwrap().data.stop_when_closed {
                    state.web.stop(&app);
                }
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

fn setup_tray(app: &mut tauri::App) -> tauri::Result<()> {
    let show = MenuItemBuilder::with_id("show", "显示主窗口").build(app)?;
    let start = MenuItemBuilder::with_id("start", "启动 Web UI").build(app)?;
    let stop = MenuItemBuilder::with_id("stop", "停止 Web UI").build(app)?;
    let quit = MenuItemBuilder::with_id("quit", "退出").build(app)?;
    let menu = MenuBuilder::new(app)
        .items(&[&show, &start, &stop, &quit])
        .build()?;
    let mut tray = TrayIconBuilder::new()
        .menu(&menu)
        .tooltip("DeepSeek Harness Shell")
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => show_main_window(app),
            "start" => {
                let state = app.state::<AppState>();
                let settings = state.settings.lock().unwrap().data.clone();
                let environment = state.environment.lock().unwrap();
                state.web.start(app, &environment, &settings);
                show_main_window(app);
            }
            "stop" => {
                app.state::<AppState>().web.stop(app);
            }
            "quit" => {
                app.state::<ExitState>().0.store(true, Ordering::SeqCst);
                app.state::<AppState>().web.stop(app);
                app.exit(0);
            }
            _ => {}
        });
    if let Some(icon) = app.default_window_icon().cloned() {
        tray = tray.icon(icon);
    }
    tray.build(app)?;
    Ok(())
}

fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}

fn initial_setup(app: &tauri::AppHandle) -> tauri::Result<()> {
    let state = app.state::<AppState>();
    {
        let mut settings = state.settings.lock().unwrap();
        settings.load(app);
    }
    {
        let settings = state.settings.lock().unwrap().data.clone();
        let mut environment = state.environment.lock().unwrap();
        environment.detect(app, &settings);
    }
    {
        let settings = state.settings.lock().unwrap().data.clone();
        state.plugins.refresh(app, &settings);
    }
    {
        let settings = state.settings.lock().unwrap().data.clone();
        let environment = state.environment.lock().unwrap();
        state.sessions.sync(app, &settings, &environment, true);
    }
    {
        let settings = state.settings.lock().unwrap().data.clone();
        let environment = state.environment.lock().unwrap();
        if matches!(environment.state, models::EnvironmentState::Ready { .. })
            && settings.auto_start_web
        {
            state.web.start(app, &environment, &settings);
        }
    }
    Ok(())
}

fn rust_smoke(app: &tauri::AppHandle) {
    use crate::models::WebServerState;
    use std::io::{Read, Write};
    use std::net::TcpStream;

    let state = app.state::<AppState>();
    let settings = state.settings.lock().unwrap().data.clone();
    println!("ENV {:?}", state.environment.lock().unwrap().state);
    println!("PLUGINS {}", state.plugins.installed.lock().unwrap().len());
    println!("SESSIONS {}", state.sessions.sessions.lock().unwrap().len());

    if std::env::var("DSH_SHELL_UPDATE_SMOKE").as_deref() == Ok("1") {
        let started = std::time::Instant::now();
        let settings = state.settings.lock().unwrap().data.clone();
        let result = {
            let mut env = state.environment.lock().unwrap();
            env.install_dsh(app, &settings, true)
        };
        println!(
            "UPDATE {} in {:?}s",
            if result { "PASS" } else { "FAIL" },
            started.elapsed().as_secs()
        );
        app.exit(if result { 0 } else { 1 });
        return;
    }

    let env = state.environment.lock().unwrap();
    state.web.start(app, &env, &settings);
    drop(env);

    let mut url = None;
    for _ in 0..60 {
        match state.web.current() {
            WebServerState::Running { url: value } => {
                url = Some(value);
                break;
            }
            WebServerState::Failed { error } => {
                println!("SMOKE FAIL WEB {error}");
                app.exit(1);
                return;
            }
            _ => std::thread::sleep(std::time::Duration::from_millis(500)),
        }
    }
    let Some(url) = url else {
        println!("SMOKE FAIL TIMEOUT");
        app.exit(1);
        return;
    };

    let host = url.replace("http://", "").trim_end_matches('/').to_string();
    let result = TcpStream::connect(&host).and_then(|mut stream| {
        let request = format!("GET / HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n");
        stream.write_all(request.as_bytes())?;
        let mut response = String::new();
        stream.read_to_string(&mut response)?;
        Ok(response)
    });
    match result {
        Ok(response) => {
            let status = response.lines().next().unwrap_or("").to_string();
            println!("WEB {status} url={url}");
            if !status.contains("200") {
                println!("SMOKE FAIL HTTP");
                app.exit(1);
                return;
            }
        }
        Err(error) => {
            println!("SMOKE FAIL HTTP {error}");
            app.exit(1);
            return;
        }
    }

    state.web.stop(app);

    if std::env::var("DSH_SHELL_PLUGIN_SMOKE").as_deref() == Ok("1") {
        let temp = std::env::temp_dir().join(format!("dsh-plugin-smoke-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&temp);
        std::fs::create_dir_all(temp.join("src")).unwrap();
        std::fs::write(
            temp.join("package.json"),
            r#"{"name":"smoke-tauri-plugin","version":"0.0.1","private":true,"dsh":{"bundle":{"patch":"patch.yml"}}}"#,
        )
        .unwrap();
        std::fs::write(temp.join("patch.yml"), "[]\n").unwrap();

        let settings = state.settings.lock().unwrap().data.clone();
        let env = state.environment.lock().unwrap();
        state
            .plugins
            .install_folder(
                app.clone(),
                temp.to_string_lossy().to_string(),
                None,
                &env,
                &settings,
            )
            .unwrap();
        let installed = state.plugins.installed.lock().unwrap().clone();
        let plugin = installed
            .iter()
            .find(|p| p.name == "smoke-tauri-plugin")
            .cloned()
            .expect("plugin not installed");
        state
            .plugins
            .update(app.clone(), plugin.name.clone(), &env, &settings)
            .unwrap();
        state
            .plugins
            .remove(app.clone(), plugin.name.clone(), &env, &settings)
            .unwrap();
        if state
            .plugins
            .installed
            .lock()
            .unwrap()
            .iter()
            .any(|p| p.name == "smoke-tauri-plugin")
        {
            println!("PLUGIN SMOKE FAIL");
            app.exit(1);
            return;
        }
        let _ = std::fs::remove_dir_all(&temp);
        println!("PLUGIN SMOKE PASS");
    }

    println!("SMOKE PASS");
    app.exit(0);
}
