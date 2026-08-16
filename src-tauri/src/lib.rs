mod commands;
mod models;
mod services;

use commands::*;
use services::*;
use tauri::{Manager, WindowEvent};

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .manage(AppState::new(SettingsService::new()))
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
            initial_setup(app.handle())?;
            if std::env::var("DSH_SHELL_SMOKE").as_deref() == Ok("1") {
                rust_smoke(app.handle());
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if matches!(event, WindowEvent::Destroyed) && window.label() == "main" {
                let app = window.app_handle().clone();
                let state = app.state::<AppState>();
                state.web.stop(&app);
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
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
        if matches!(environment.state, models::EnvironmentState::Ready { .. }) && settings.auto_start_web {
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
        state.plugins.install_folder(app.clone(), temp.to_string_lossy().to_string(), None, &env, &settings).unwrap();
        let installed = state.plugins.installed.lock().unwrap().clone();
        let plugin = installed.iter().find(|p| p.name == "smoke-tauri-plugin").cloned().expect("plugin not installed");
        state.plugins.update(app.clone(), plugin.name.clone(), &env, &settings).unwrap();
        state.plugins.remove(app.clone(), plugin.name.clone(), &env, &settings).unwrap();
        if state.plugins.installed.lock().unwrap().iter().any(|p| p.name == "smoke-tauri-plugin") {
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
