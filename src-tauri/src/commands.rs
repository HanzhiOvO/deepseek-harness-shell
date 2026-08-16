use crate::models::*;
use crate::services::*;
use std::fs;
use tauri::async_runtime::spawn_blocking;
use tauri::{AppHandle, Manager, State, WebviewUrl, WebviewWindowBuilder};

fn settings_clone(state: &State<AppState>) -> AppSettingsData {
    state.settings.lock().unwrap().data.clone()
}

#[tauri::command]
pub fn app_bootstrap(app: AppHandle, state: State<AppState>) -> BootstrapPayload {
    let settings = settings_clone(&state);
    let environment = state.environment.lock().unwrap();
    let logs = state.logs.lock().unwrap();
    let plugins = state.plugins.installed.lock().unwrap().clone();
    let profiles = state.plugins.profiles.lock().unwrap().clone();
    let profile_name = state.plugins.profile_name.lock().unwrap().clone();
    let sessions = state.sessions.sessions.lock().unwrap().clone();
    let data_dir = app.path().app_data_dir().unwrap_or_default();
    let dsh_home = dsh_home_directory(&settings);
    BootstrapPayload {
        platform: std::env::consts::OS.to_string(),
        version: app.package_info().version.to_string(),
        data_dirs: DataDirs {
            dsh_home: dsh_home.clone(),
            profile_directory: format!("{dsh_home}/profiles/{profile_name}"),
            settings_directory: data_dir.to_string_lossy().to_string(),
            plugin_sources_directory: data_dir.join("PluginSources").to_string_lossy().to_string(),
        },
        settings,
        environment: EnvironmentPayload {
            state: environment.state.clone(),
            tools: environment.tools.clone(),
            is_working: environment.is_working,
        },
        web: state.web.current(),
        sessions,
        plugins,
        profiles,
        profile_name,
        logs: logs.snapshot_json(),
    }
}

#[tauri::command]
pub async fn env_detect(app: AppHandle) -> Result<EnvironmentState, String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        env.detect(&app, &settings);
        env.state.clone()
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn env_install_dsh(app: AppHandle) -> Result<bool, String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        env.install_dsh(&app, &settings, false)
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn env_update_dsh(app: AppHandle) -> Result<bool, String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        env.install_dsh(&app, &settings, true)
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn env_install_node(app: AppHandle) -> Result<bool, String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        env.install_node(&app, &settings)
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn env_ensure_pnpm(app: AppHandle) -> Result<bool, String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        env.ensure_pnpm(&app, &settings)
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn web_start(app: AppHandle, state: State<AppState>) -> WebServerState {
    let settings = settings_clone(&state);
    let env = state.environment.lock().unwrap();
    state.web.start(&app, &env, &settings);
    state.web.current()
}

#[tauri::command]
pub fn web_stop(app: AppHandle, state: State<AppState>) -> WebServerState {
    state.web.stop(&app);
    state.web.current()
}

#[tauri::command]
pub fn web_open_external(state: State<AppState>) {
    if let WebServerState::Running { url } = state.web.current() {
        open_external(&url);
    }
}

#[tauri::command]
pub fn web_open_session(app: AppHandle, state: State<AppState>, request: OpenSessionRequest) -> Result<(), String> {
    if !matches!(state.web.current(), WebServerState::Running { .. }) {
        let settings = settings_clone(&state);
        let env = state.environment.lock().unwrap();
        state.web.start(&app, &env, &settings);
    }
    let WebServerState::Running { url } = state.web.current() else {
        return Err("Web 服务尚未运行".into());
    };

    let label = format!("harness-{}", sanitize_label(&request.id));
    if let Some(existing) = app.get_webview_window(&label) {
        let _ = existing.set_focus();
        return Ok(());
    }

    let script = session_open_script(&request.id, &request.display_title);
    let window = WebviewWindowBuilder::new(&app, &label, WebviewUrl::External(url.parse::<url::Url>().map_err(|e| e.to_string())?))
        .title(format!("Harness · {}", request.display_title))
        .inner_size(1180.0, 780.0)
        .min_inner_size(860.0, 620.0)
        .initialization_script(&script)
        .build()
        .map_err(|e| e.to_string())?;
    let _ = window.set_focus();
    Ok(())
}

#[tauri::command]
pub fn web_open_window(app: AppHandle, state: State<AppState>) -> Result<(), String> {
    let WebServerState::Running { url } = state.web.current() else {
        return Err("Web 服务尚未运行".into());
    };
    if let Some(existing) = app.get_webview_window("harness-main") {
        let _ = existing.set_focus();
        return Ok(());
    }
    WebviewWindowBuilder::new(&app, "harness-main", WebviewUrl::External(url.parse::<url::Url>().map_err(|e| e.to_string())?))
        .title("DeepSeek Harness")
        .inner_size(1180.0, 780.0)
        .min_inner_size(860.0, 620.0)
        .build()
        .map_err(|_| "无法创建窗口".to_string())?;
    Ok(())
}

#[tauri::command]
pub async fn sessions_sync(app: AppHandle) -> Result<(), String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let env = state.environment.lock().unwrap();
        state.sessions.sync(&app, &settings, &env, true);
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn sessions_toggle_pin(app: AppHandle, state: State<AppState>, id: String) -> bool {
    state.settings.lock().unwrap().toggle_pin(&app, &id)
}

#[tauri::command]
pub fn sessions_reveal(path: String) {
    reveal_path(&path);
}

#[tauri::command]
pub async fn plugins_refresh(app: AppHandle) -> Result<(), String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        state.plugins.refresh(&app, &settings);
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn plugins_set_profile(app: AppHandle, state: State<AppState>, name: String) {
    let settings = settings_clone(&state);
    state.plugins.set_profile(&app, &settings, name);
}

#[tauri::command]
pub async fn plugins_install(app: AppHandle, draft: InstallDraft) -> Result<(), String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        if env.pnpm_path().is_none() && !env.ensure_pnpm(&app, &settings) {
            return Err("无法准备 pnpm，请查看运行日志".into());
        }
        match draft.kind.as_str() {
            "github" => state.plugins.install_github(app.clone(), draft.github_text.unwrap_or_default(), &env, &settings),
            "npm" => state.plugins.install_npm(app.clone(), draft.npm_text.unwrap_or_default(), &env, &settings),
            "zip" => state.plugins.install_zip(app.clone(), draft.file_path.unwrap_or_default(), &env, &settings),
            "folder" => state.plugins.install_folder(app.clone(), draft.file_path.unwrap_or_default(), None, &env, &settings),
            _ => Err("未知安装方式".into()),
        }
    })
    .await
    .map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn plugins_update(app: AppHandle, name: String) -> Result<(), String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        if env.pnpm_path().is_none() && !env.ensure_pnpm(&app, &settings) {
            return Err("无法准备 pnpm，请查看运行日志".into());
        }
        state.plugins.update(app.clone(), name, &env, &settings)
    })
    .await
    .map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn plugins_remove(app: AppHandle, name: String) -> Result<(), String> {
    spawn_blocking(move || {
        let state = app.state::<AppState>();
        let settings = settings_clone(&state);
        let mut env = state.environment.lock().unwrap();
        if env.pnpm_path().is_none() && !env.ensure_pnpm(&app, &settings) {
            return Err("无法准备 pnpm，请查看运行日志".into());
        }
        state.plugins.remove(app.clone(), name, &env, &settings)
    })
    .await
    .map_err(|error| error.to_string())?
}

#[tauri::command]
pub async fn plugins_pick_zip(app: AppHandle) -> Result<Option<String>, String> {
    spawn_blocking(move || {
        use tauri_plugin_dialog::DialogExt;
        let picked = app.dialog().file().add_filter("ZIP", &["zip"]).blocking_pick_file();
        match picked {
            Some(path) => path.into_path().ok().map(|p| p.to_string_lossy().to_string()),
            None => None,
        }
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn plugins_pick_folder(app: AppHandle) -> Result<Option<String>, String> {
    spawn_blocking(move || {
        use tauri_plugin_dialog::DialogExt;
        match app.dialog().file().blocking_pick_folder() {
            Some(path) => path.into_path().ok().map(|p| p.to_string_lossy().to_string()),
            None => None,
        }
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn settings_update(app: AppHandle, state: State<AppState>, patch: serde_json::Value) -> AppSettingsData {
    let updated = state.settings.lock().unwrap().update(&app, patch);
    state.environment.lock().unwrap().refresh_overrides(&updated);
    updated
}

#[tauri::command]
pub fn settings_reset(app: AppHandle, state: State<AppState>) -> AppSettingsData {
    state.settings.lock().unwrap().reset(&app)
}

#[tauri::command]
pub fn logs_clear(state: State<AppState>, source: Option<String>) {
    state.logs.lock().unwrap().clear(source.as_deref());
}

#[tauri::command]
pub async fn logs_export(app: AppHandle, text: String, default_name: String) -> Result<bool, String> {
    spawn_blocking(move || {
        use tauri_plugin_dialog::DialogExt;
        let picked = app.dialog().file().set_file_name(&default_name).add_filter("文本", &["txt"]).blocking_save_file();
        if let Some(path) = picked.and_then(|p| p.into_path().ok()) {
            fs::write(path, text).is_ok()
        } else {
            false
        }
    })
    .await
    .map_err(|error| error.to_string())
}

#[tauri::command]
pub fn shell_open_external(url: String) {
    open_external(&url);
}

#[tauri::command]
pub fn shell_reveal(path: String) {
    reveal_path(&path);
}

#[tauri::command]
pub fn shell_open_path(path: String) {
    open_path(&path);
}

// MARK: - 辅助

fn session_open_script(id: &str, title: &str) -> String {
    let id_json = serde_json::to_string(id).unwrap_or_else(|_| "null".into());
    let title_json = serde_json::to_string(title).unwrap_or_else(|_| "null".into());
    format!(
        r#"(function () {{
  function fiberOf(el) {{
    var key = Object.keys(el).find(function (k) {{ return k.indexOf('__reactFiber') === 0; }});
    return key ? el[key] : null;
  }}
  function nameOf(f) {{
    if (!f) return '';
    if (f.elementType && f.elementType.name) return String(f.elementType.name);
    return typeof f.type === 'string' ? f.type : '';
  }}
  var target = {id_json};
  var title = {title_json};
  var rows = Array.from(document.querySelectorAll('[role="treeitem"]'));
  for (var i = 0; i < rows.length; i++) {{
    var f = fiberOf(rows[i]);
    while (f) {{
      if (nameOf(f) === 'SessionNodeItem') {{
        var node = f.memoizedProps && f.memoizedProps.node;
        if (node && node.id === target) {{ rows[i].click(); return; }}
      }}
      f = f.return;
    }}
  }}
  if (title) {{
    var norm = function (s) {{ return (s || '').trim().replace(/\s+/g, ' '); }};
    var prefix = norm(title).slice(0, 18);
    for (var j = 0; j < rows.length; j++) {{
      var span = rows[j].querySelector('.YDXeBa_title');
      if (span && norm(span.textContent).slice(0, prefix.length) === prefix && prefix.length > 0) {{
        rows[j].click(); return;
      }}
    }}
  }}
}})();"#
    )
}

fn sanitize_label(id: &str) -> String {
    id.chars().filter(|c| c.is_ascii_alphanumeric() || *c == '-').take(48).collect::<String>()
}

fn open_external(url: &str) {
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(url).spawn();
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("cmd").args(["/C", "start", "", url]).spawn();
    #[cfg(target_os = "linux")]
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

fn open_path(path: &str) {
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(path).spawn();
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("cmd").args(["/C", "start", "", path]).spawn();
    #[cfg(target_os = "linux")]
    let _ = std::process::Command::new("xdg-open").arg(path).spawn();
}

fn reveal_path(path: &str) {
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").args(["-R", path]).spawn();
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("explorer").arg(format!("/select,{path}")).spawn();
    #[cfg(target_os = "linux")]
    let _ = {
        if let Some(parent) = Path::new(path).parent() {
            std::process::Command::new("xdg-open").arg(parent).spawn()
        } else {
            Err(std::io::Error::new(std::io::ErrorKind::NotFound, "no parent"))
        }
    };
}
