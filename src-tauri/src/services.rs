use crate::models::*;
use serde_json::json;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{mpsc, Arc, Mutex};
use tauri::{AppHandle, Emitter, Manager};

static LOG_ID: AtomicU64 = AtomicU64::new(1);

pub const LOG_SOURCES: [&str; 4] = ["environment", "web", "plugins", "sessions"];

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub fn make_log(source: &str, level: &str, text: impl Into<String>) -> LogEntry {
    LogEntry {
        id: format!("log-{}", LOG_ID.fetch_add(1, Ordering::Relaxed)),
        date: now_ms(),
        source: source.to_string(),
        level: level.to_string(),
        text: text.into(),
    }
}

pub fn emit_log(app: &AppHandle, source: &str, level: &str, text: impl Into<String>) {
    let entry = make_log(source, level, text);
    let _ = app.emit("event:log", &entry);
}

pub struct LogStore {
    entries: HashMap<String, Vec<LogEntry>>,
}

impl LogStore {
    pub fn new() -> Self {
        Self { entries: HashMap::new() }
    }

    pub fn clear(&mut self, source: Option<&str>) {
        if let Some(source) = source {
            self.entries.remove(source);
        } else {
            self.entries.clear();
        }
    }

    pub fn snapshot_json(&self) -> serde_json::Value {
        let mut root = json!({});
        for source in LOG_SOURCES {
            let list = self.entries.get(source).cloned().unwrap_or_default();
            root[source] = json!(list.into_iter().rev().take(240).rev().collect::<Vec<_>>());
        }
        root
    }
}

pub fn expand_tilde(path: &str) -> String {
    if path == "~" {
        return env::var("HOME").or_else(|_| env::var("USERPROFILE")).unwrap_or_default();
    }
    if let Some(rest) = path.strip_prefix("~/").or_else(|| path.strip_prefix("~\\")) {
        if let Ok(home) = env::var("HOME").or_else(|_| env::var("USERPROFILE")) {
            return format!("{home}{}", std::path::MAIN_SEPARATOR.to_string().as_str()) + rest;
        }
    }
    path.to_string()
}

pub fn dsh_home_directory(settings: &AppSettingsData) -> String {
    if !settings.dsh_home.trim().is_empty() {
        return expand_tilde(settings.dsh_home.trim());
    }
    if let Ok(env_home) = env::var("DSH_HOME") {
        if !env_home.trim().is_empty() {
            return expand_tilde(env_home.trim());
        }
    }
    let home = env::var("HOME").or_else(|_| env::var("USERPROFILE")).unwrap_or_default();
    format!("{}/.dsh", home.trim_end_matches('/'))
}

pub struct SettingsService {
    pub data: AppSettingsData,
    loaded: bool,
}

impl SettingsService {
    pub fn new() -> Self {
        Self { data: AppSettingsData::default(), loaded: false }
    }

    pub fn load(&mut self, app: &AppHandle) {
        let dir = env::var("DSH_SHELL_USER_DATA")
            .map(PathBuf::from)
            .ok()
            .or_else(|| app.path().app_data_dir().ok());
        if let Some(dir) = dir {
            let _ = fs::create_dir_all(&dir);
            let path = dir.join("settings.json");
            if let Ok(raw) = fs::read_to_string(&path) {
                if let Ok(mut parsed) = serde_json::from_str::<AppSettingsData>(&raw) {
                    parsed.web_port = parsed.web_port.min(65535);
                    self.data = parsed;
                }
            }
        }
        self.loaded = true;
        self.persist(app);
    }

    pub fn update(&mut self, app: &AppHandle, patch: serde_json::Value) -> AppSettingsData {
        if let Some(object) = patch.as_object() {
            if let Some(value) = object.get("autoStartWeb").and_then(|v| v.as_bool()) { self.data.auto_start_web = value; }
            if let Some(value) = object.get("autoInstallDsh").and_then(|v| v.as_bool()) { self.data.auto_install_dsh = value; }
            if let Some(value) = object.get("stopWhenClosed").and_then(|v| v.as_bool()) { self.data.stop_when_closed = value; }
            if let Some(value) = object.get("telemetryDisabled").and_then(|v| v.as_bool()) { self.data.telemetry_disabled = value; }
            if let Some(value) = object.get("webPort").and_then(|v| v.as_u64()) { self.data.web_port = (value as u32).min(65535); }
            if let Some(value) = object.get("profileName").and_then(|v| v.as_str()) {
                self.data.profile_name = if value.trim().is_empty() { "web".into() } else { value.trim().to_string() };
            }
            if let Some(value) = object.get("apiKey").and_then(|v| v.as_str()) { self.data.api_key = value.to_string(); }
            if let Some(value) = object.get("customDshPath").and_then(|v| v.as_str()) { self.data.custom_dsh_path = value.to_string(); }
            if let Some(value) = object.get("dshHome").and_then(|v| v.as_str()) { self.data.dsh_home = value.to_string(); }
            if let Some(value) = object.get("appearance").and_then(|v| v.as_str()) { self.data.appearance = value.to_string(); }
            if let Some(value) = object.get("pinnedSessionIds").and_then(|v| v.as_array()) {
                self.data.pinned_session_ids = value.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect();
            }
        }
        self.persist(app);
        let _ = app.emit("event:settings", &self.data);
        self.data.clone()
    }

    pub fn reset(&mut self, app: &AppHandle) -> AppSettingsData {
        self.data = AppSettingsData::default();
        self.persist(app);
        let _ = app.emit("event:settings", &self.data);
        self.data.clone()
    }

    pub fn toggle_pin(&mut self, app: &AppHandle, id: &str) -> bool {
        let pinned = self.data.pinned_session_ids.contains(&id.to_string());
        if pinned {
            self.data.pinned_session_ids.retain(|item| item != id);
        } else {
            self.data.pinned_session_ids.push(id.to_string());
        }
        self.persist(app);
        let _ = app.emit("event:settings", &self.data);
        !pinned
    }

    fn persist(&self, app: &AppHandle) {
        if !self.loaded {
            return;
        }
        if let Ok(dir) = app.path().app_data_dir() {
            let _ = fs::create_dir_all(&dir);
            let path = dir.join("settings.json");
            if let Ok(data) = serde_json::to_string_pretty(&self.data) {
                let _ = fs::write(&path, data);
            }
        }
    }
}

// MARK: - 环境服务

pub struct EnvironmentService {
    pub tools: Toolchain,
    pub state: EnvironmentState,
    pub is_working: bool,
    pub spawn_environment: HashMap<String, String>,
    extra_directories: Vec<String>,
}

impl EnvironmentService {
    pub fn new() -> Self {
        let extra_directories = candidate_directories();
        let spawn_environment = base_environment(&extra_directories);
        Self {
            tools: Toolchain::default(),
            state: EnvironmentState::Idle { label: "等待检测".into(), can_install: false, detail: String::new() },
            is_working: false,
            spawn_environment,
            extra_directories,
        }
    }

    pub fn dsh_path(&self) -> Option<String> {
        self.tools.dsh.as_ref().map(|tool| tool.path.clone())
    }

    pub fn npm_path(&self) -> Option<String> {
        self.tools.npm.as_ref().map(|tool| tool.path.clone())
    }

    pub fn pnpm_path(&self) -> Option<String> {
        self.tools.pnpm.as_ref().map(|tool| tool.path.clone())
    }

    pub fn detect(&mut self, app: &AppHandle, settings: &AppSettingsData) {
        if self.is_working {
            return;
        }
        self.is_working = true;
        self.state = EnvironmentState::Checking { label: "正在检测环境…".into(), can_install: false, detail: String::new() };
        emit_log(app, "environment", "info", "开始检测 DeepSeek Harness 运行环境");

        let mut dsh: Option<ToolInfo> = None;
        let custom = settings.custom_dsh_path.trim().to_string();
        if !custom.is_empty() {
            dsh = tool_version("dsh", &expand_tilde(&custom), &self.spawn_environment);
        }

        let mut by_name: HashMap<String, Option<ToolInfo>> = HashMap::new();
        by_name.insert("dsh".into(), dsh);
        for name in ["node", "npm", "dsh", "pnpm", "git", "brew"] {
            if by_name.get(name).and_then(|v| v.as_ref()).is_some() {
                continue;
            }
            let mut found = None;
            for candidate in candidates_for(name, &self.extra_directories).into_iter().take(12) {
                if let Some(tool) = tool_version(name, &candidate, &self.spawn_environment) {
                    found = Some(tool);
                    break;
                }
            }
            by_name.insert(name.into(), found);
        }

        let mut known_bins: Vec<String> = Vec::new();
        for tool in by_name.values().flatten() {
            if let Some(parent) = Path::new(&tool.path).parent() {
                if let Some(path) = parent.to_str() {
                    known_bins.push(path.to_string());
                }
            }
        }
        for dir in &self.extra_directories {
            if Path::new(dir).exists() {
                known_bins.push(dir.clone());
            }
        }
        known_bins.sort();
        known_bins.dedup();

        self.tools = Toolchain {
            dsh: by_name.get("dsh").cloned().flatten(),
            node: by_name.get("node").cloned().flatten(),
            npm: by_name.get("npm").cloned().flatten(),
            pnpm: by_name.get("pnpm").cloned().flatten(),
            git: by_name.get("git").cloned().flatten(),
            brew: by_name.get("brew").cloned().flatten(),
            known_bin_directories: known_bins,
        };
        self.spawn_environment = base_environment(&self.tools.known_bin_directories);
        self.apply_settings_overrides(settings);
        let _ = app.emit("event:tools", &self.tools);

        let summary = [&self.tools.dsh, &self.tools.node, &self.tools.npm, &self.tools.pnpm, &self.tools.git, &self.tools.brew]
            .into_iter()
            .flatten()
            .map(|tool| format!("{} {}", tool.name, tool.version.as_deref().unwrap_or("?")))
            .collect::<Vec<_>>()
            .join(", ");
        if summary.is_empty() {
            emit_log(app, "environment", "info", "未检测到任何工具链");
        } else {
            emit_log(app, "environment", "info", format!("检测到工具链：{summary}"));
        }

        if self.tools.dsh.is_some() {
            self.state = EnvironmentState::Ready {
                label: "环境就绪".into(),
                can_install: false,
                detail: format!("dsh {}", self.tools.dsh.as_ref().and_then(|t| t.version.clone()).unwrap_or_default()),
            };
            emit_log(app, "environment", "success", "dsh 可用");
        } else if self.tools.node.is_some() && self.tools.npm.is_some() {
            self.state = EnvironmentState::MissingDsh {
                label: "缺少 dsh".into(),
                can_install: true,
                detail: "检测到 Node.js 与 npm，可自动安装 @deepseek-ai/dsh".into(),
            };
        } else if self.tools.node.is_some() {
            self.state = EnvironmentState::MissingNpm {
                label: "缺少 npm".into(),
                can_install: false,
                detail: "检测到 Node.js，但 npm 不可用".into(),
            };
        } else if self.tools.brew.is_some() {
            self.state = EnvironmentState::MissingNode {
                label: "缺少 Node.js".into(),
                can_install: true,
                detail: "检测到 Homebrew，可自动安装 Node.js".into(),
            };
        } else {
            self.state = EnvironmentState::MissingNode {
                label: "缺少 Node.js".into(),
                can_install: false,
                detail: "未找到 Node.js，请从 https://nodejs.org 安装".into(),
            };
        }
        let _ = app.emit("event:env-state", &self.state);
        self.is_working = false;
    }

    pub fn refresh_overrides(&mut self, settings: &AppSettingsData) {
        self.apply_settings_overrides(settings);
    }

    pub fn install_dsh(&mut self, app: &AppHandle, settings: &AppSettingsData, update: bool) -> bool {
        if self.is_working {
            return false;
        }
        if self.npm_path().is_none() {
            self.state = EnvironmentState::Failed { label: "缺少 npm，无法安装 dsh".into(), can_install: false, detail: String::new() };
            let _ = app.emit("event:env-state", &self.state);
            return false;
        }
        let verb = if update { "升级" } else { "安装" };
        self.is_working = true;
        self.state = EnvironmentState::Installing { label: format!("正在{verb} @deepseek-ai/dsh…"), can_install: false, detail: String::new() };
        let _ = app.emit("event:env-state", &self.state);
        emit_log(app, "environment", "command", format!("准备{verb} @deepseek-ai/dsh"));

        let prefix = npm_writable_prefix(&self);
        let _ = fs::create_dir_all(format!("{prefix}/bin"));
        let package = if update { "@deepseek-ai/dsh@latest" } else { "@deepseek-ai/dsh" };
        let mut env = self.spawn_environment.clone();
        env.insert("npm_config_prefix".into(), prefix.clone());
        env.insert("npm_config_loglevel".into(), "warn".into());

        emit_log(app, "environment", "command", format!("npm install --global --prefix {prefix} {package}"));
        let result = run_streaming_wait(app, "environment", self.npm_path().unwrap(), &["install", "--global", "--prefix", &prefix, package, "--no-audit", "--no-fund"], Some(&env));

        self.is_working = false;
        if result.code == Some(0) {
            if !self.tools.known_bin_directories.contains(&format!("{prefix}/bin")) {
                self.tools.known_bin_directories.push(format!("{prefix}/bin"));
            }
            self.spawn_environment = base_environment(&self.tools.known_bin_directories);
            self.apply_settings_overrides(settings);
            emit_log(app, "environment", "success", format!("@deepseek-ai/dsh {verb}完成"));
            self.detect(app, settings);
            self.tools.dsh.is_some()
        } else {
            self.state = EnvironmentState::Failed { label: format!("dsh {verb}失败"), can_install: false, detail: result.stderr.clone() };
            let _ = app.emit("event:env-state", &self.state);
            false
        }
    }

    pub fn install_node(&mut self, app: &AppHandle, settings: &AppSettingsData) -> bool {
        if self.is_working {
            return false;
        }
        let Some(brew) = self.tools.brew.clone() else {
            self.state = EnvironmentState::Failed { label: "未找到 Homebrew".into(), can_install: false, detail: String::new() };
            return false;
        };
        self.is_working = true;
        self.state = EnvironmentState::Installing { label: "正在通过 Homebrew 安装 Node.js…".into(), can_install: false, detail: String::new() };
        emit_log(app, "environment", "command", "brew install node");
        let result = run_streaming_wait(app, "environment", brew.path, &["install", "node"], Some(&self.spawn_environment));
        self.is_working = false;
        if result.code == Some(0) {
            self.detect(app, settings);
            true
        } else {
            self.state = EnvironmentState::Failed { label: "Node.js 安装失败".into(), can_install: false, detail: result.stderr };
            let _ = app.emit("event:env-state", &self.state);
            false
        }
    }

    pub fn ensure_pnpm(&mut self, app: &AppHandle, settings: &AppSettingsData) -> bool {
        if self.is_working {
            return false;
        }
        if self.tools.pnpm.is_some() {
            return true;
        }
        if self.tools.npm.is_none() {
            emit_log(app, "environment", "error", "缺少 npm，无法安装 pnpm");
            return false;
        }
        emit_log(app, "environment", "info", "未检测到 pnpm，正在准备…");
        let corepack = find_executable("corepack", &self.extra_directories);
        if let Some(corepack_path) = corepack {
            let result = run_streaming_wait(app, "environment", corepack_path.clone(), &["prepare", "pnpm@latest", "--activate"], Some(&self.spawn_environment));
            if result.code == Some(0) {
                if let Ok(data_dir) = app.path().app_data_dir() {
                    let shim_dir = data_dir.join("bin");
                    let _ = fs::create_dir_all(&shim_dir);
                    let shim = shim_dir.join(if cfg!(windows) { "pnpm.cmd" } else { "pnpm" });
                    let script = if cfg!(windows) {
                        format!("@echo off\r\n\"{}\" pnpm %*\r\n", corepack_path)
                    } else {
                        format!("#!/bin/sh\nexec '{}' pnpm \"$@\"\n", corepack_path)
                    };
                    if fs::write(&shim, script).is_ok() {
                        #[cfg(unix)]
                        {
                            use std::os::unix::fs::PermissionsExt;
                            let _ = fs::set_permissions(&shim, fs::Permissions::from_mode(0o755));
                        }
                        let mut dirs = self.tools.known_bin_directories.clone();
                        dirs.insert(0, shim_dir.to_string_lossy().to_string());
                        if let Some(tool) = tool_version("pnpm", shim.to_string_lossy().as_ref(), &base_environment(&dirs)) {
                            self.tools.pnpm = Some(tool);
                            self.tools.known_bin_directories = dirs;
                            self.spawn_environment = base_environment(&self.tools.known_bin_directories);
                            self.apply_settings_overrides(settings);
                            let _ = app.emit("event:tools", &self.tools);
                            emit_log(app, "environment", "success", "pnpm 已通过 Corepack 激活");
                            return true;
                        }
                    }
                }
            }
        }
        let prefix = npm_writable_prefix(self);
        let _ = fs::create_dir_all(format!("{prefix}/bin"));
        let mut env = self.spawn_environment.clone();
        env.insert("npm_config_prefix".into(), prefix.clone());
        let result = run_streaming_wait(app, "environment", self.npm_path().unwrap(), &["install", "--global", "--prefix", &prefix, "pnpm", "--no-audit", "--no-fund"], Some(&env));
        if result.code == Some(0) {
            let mut dirs = self.tools.known_bin_directories.clone();
            dirs.insert(0, format!("{prefix}/bin"));
            if let Some(tool) = tool_version("pnpm", &format!("{prefix}/bin/pnpm"), &base_environment(&dirs)) {
                self.tools.pnpm = Some(tool);
                self.tools.known_bin_directories = dirs;
                self.spawn_environment = base_environment(&self.tools.known_bin_directories);
                self.apply_settings_overrides(settings);
                let _ = app.emit("event:tools", &self.tools);
                emit_log(app, "environment", "success", "pnpm 安装完成");
                return true;
            }
        }
        emit_log(app, "environment", "error", "pnpm 安装失败，请查看日志");
        false
    }

    fn apply_settings_overrides(&mut self, settings: &AppSettingsData) {
        if !settings.dsh_home.trim().is_empty() {
            self.spawn_environment.insert("DSH_HOME".into(), expand_tilde(settings.dsh_home.trim()));
        } else {
            self.spawn_environment.remove("DSH_HOME");
        }
        if settings.telemetry_disabled {
            self.spawn_environment.insert("DSH_TELEMETRY_DISABLED".into(), "1".into());
        } else {
            self.spawn_environment.remove("DSH_TELEMETRY_DISABLED");
        }
    }
}

// MARK: - 工具链探测辅助

fn candidate_directories() -> Vec<String> {
    let home = env::var("HOME").or_else(|_| env::var("USERPROFILE")).unwrap_or_default();
    let mut dirs: Vec<String> = Vec::new();
    let mut push = |path: String| {
        let normalized = normalize_path(&path);
        if !dirs.contains(&normalized) {
            dirs.push(normalized);
        }
    };
    if let Ok(path) = env::var("PATH") {
        let separator = if cfg!(windows) { ';' } else { ':' };
        for entry in path.split(separator) {
            if !entry.is_empty() {
                push(entry.to_string());
            }
        }
    }
    for dir in [
        format!("{home}/.local/bin"),
        format!("{home}/.npm-global/bin"),
        format!("{home}/Library/pnpm"),
        "/opt/homebrew/bin".into(),
        "/opt/homebrew/opt/node/bin".into(),
        "/opt/homebrew/opt/corepack/bin".into(),
        "/opt/homebrew/opt/pnpm/bin".into(),
        "/usr/local/bin".into(),
        "/usr/local/opt/node/bin".into(),
        "/usr/bin".into(),
        "/bin".into(),
        format!("{home}/.volta/bin"),
        format!("{home}/.asdf/shims"),
        format!("{home}/.mise/shims"),
        format!("{home}/.local/share/mise/shims"),
        format!("{home}/miniconda3/bin"),
        format!("{home}/anaconda3/bin"),
        format!("{home}/AppData/Roaming/npm"),
        format!("{home}/AppData/Local/Volta/bin"),
        "C:\\Program Files\\nodejs".into(),
    ] {
        push(dir);
    }
    dirs
}

fn normalize_path(path: &str) -> String {
    let expanded = expand_tilde(path);
    std::fs::canonicalize(&expanded).map(|p| p.to_string_lossy().to_string()).unwrap_or(expanded)
}

fn candidates_for(name: &str, dirs: &[String]) -> Vec<String> {
    let extensions: &[&str] = if cfg!(windows) { &[".exe", ".cmd", ".bat", ""] } else { &[""] };
    let mut result = Vec::new();
    for dir in dirs {
        for extension in extensions {
            result.push(format!("{}/{}{}", dir.trim_end_matches('/'), name, extension));
        }
    }
    result
}

fn find_executable(name: &str, dirs: &[String]) -> Option<String> {
    candidates_for(name, dirs).into_iter().find(|path| Path::new(path).exists())
}

fn tool_version(name: &str, path: &str, env_map: &HashMap<String, String>) -> Option<ToolInfo> {
    if !Path::new(path).exists() {
        return None;
    }
    let result = run_capture(path, &["--version"], Some(env_map));
    if result.code != Some(0) && result.code != None {
        return None;
    }
    let version = result.stdout.lines().next().unwrap_or("").trim().to_string();
    Some(ToolInfo { name: name.into(), path: path.to_string(), version: if version.is_empty() { None } else { Some(version) } })
}

fn base_environment(extra_dirs: &[String]) -> HashMap<String, String> {
    let mut env: HashMap<String, String> = env::vars().collect();
    let path = env.get("PATH").cloned().unwrap_or_default();
    let separator = if cfg!(windows) { ';' } else { ':' };
    let mut entries: Vec<String> = path.split(separator).filter(|e| !e.is_empty()).map(|e| e.to_string()).collect();
    for dir in extra_dirs.iter().rev() {
        if !entries.iter().any(|entry| normalize_path(entry) == normalize_path(dir)) {
            entries.insert(0, dir.clone());
        }
    }
    env.insert("PATH".into(), entries.join(&separator.to_string()));
    env
}

fn npm_writable_prefix(service: &EnvironmentService) -> String {
    let fallback = if cfg!(windows) {
        let home = env::var("USERPROFILE").unwrap_or_default();
        format!("{home}/AppData/Roaming/npm")
    } else {
        let home = env::var("HOME").unwrap_or_default();
        format!("{home}/.local")
    };
    if let Some(npm) = service.npm_path() {
        let result = run_capture_owned(&npm, vec!["config".into(), "get".into(), "prefix".into()], Some(&service.spawn_environment));
        let prefix = result.stdout.lines().next().unwrap_or("").trim().to_string();
        if !prefix.is_empty() && Path::new(&prefix).exists() {
            return prefix;
        }
    }
    fallback
}

fn base_command(program: &str, args: &[String], env_map: Option<&HashMap<String, String>>) -> (Command, Vec<String>) {
    let (mut command, actual_args) = if cfg!(windows) && (program.ends_with(".cmd") || program.ends_with(".bat")) {
        let cmd = Command::new("cmd.exe");
        let mut actual = vec!["/C".to_string(), program.to_string()];
        actual.extend(args.iter().cloned());
        (cmd, actual)
    } else {
        (Command::new(program), args.to_vec())
    };
    if let Some(env_map) = env_map {
        command.envs(env_map.iter());
    }
    command.stdin(Stdio::null());
    (command, actual_args)
}

pub struct CommandOutput {
    pub code: Option<i32>,
    pub stdout: String,
    pub stderr: String,
}

fn run_capture(program: &str, args: &[&str], env_map: Option<&HashMap<String, String>>) -> CommandOutput {
    let owned: Vec<String> = args.iter().map(|arg| arg.to_string()).collect();
    run_capture_owned(program, owned, env_map)
}

fn run_capture_owned(program: &str, args: Vec<String>, env_map: Option<&HashMap<String, String>>) -> CommandOutput {
    let (mut command, actual_args) = base_command(program, &args, env_map);
    command.args(&actual_args);
    match command.output() {
        Ok(output) => CommandOutput {
            code: output.status.code(),
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
        },
        Err(error) => CommandOutput { code: None, stdout: String::new(), stderr: error.to_string() },
    }
}

pub fn run_streaming_wait(app: &AppHandle, source: &str, program: String, args: &[&str], env_map: Option<&HashMap<String, String>>) -> CommandOutput {
    let (tx, rx) = mpsc::channel::<CommandOutput>();
    match spawn_streaming_owned(
        app,
        source,
        program,
        args.iter().map(|s| s.to_string()).collect(),
        env_map,
        move |code, error| {
            let _ = tx.send(CommandOutput { code, stdout: String::new(), stderr: error.unwrap_or_default() });
        },
    ) {
        Ok(_pid) => rx.recv().unwrap_or(CommandOutput { code: None, stdout: String::new(), stderr: "进程未返回".into() }),
        Err(error) => CommandOutput { code: None, stdout: String::new(), stderr: error },
    }
}

pub fn spawn_streaming_owned<F>(
    app: &AppHandle,
    source: &str,
    program: String,
    args: Vec<String>,
    env_map: Option<&HashMap<String, String>>,
    on_exit: F,
) -> Result<u32, String>
where
    F: FnOnce(Option<i32>, Option<String>) + Send + 'static,
{
    spawn_streaming_core(app, source, program, args, env_map, None, on_exit)
}

pub fn spawn_streaming_with_lines<F>(
    app: &AppHandle,
    source: &str,
    program: String,
    args: Vec<String>,
    env_map: Option<&HashMap<String, String>>,
    on_line: impl Fn(&str, bool) + Send + Sync + 'static,
    on_exit: F,
) -> Result<u32, String>
where
    F: FnOnce(Option<i32>, Option<String>) + Send + 'static,
{
    spawn_streaming_core(app, source, program, args, env_map, Some(Box::new(on_line)), on_exit)
}

fn spawn_streaming_core<F>(
    app: &AppHandle,
    source: &str,
    program: String,
    args: Vec<String>,
    env_map: Option<&HashMap<String, String>>,
    on_line: Option<Box<dyn Fn(&str, bool) + Send + Sync>>,
    on_exit: F,
) -> Result<u32, String>
where
    F: FnOnce(Option<i32>, Option<String>) + Send + 'static,
{
    let (mut command, actual_args) = base_command(&program, &args, env_map);
    command.args(&actual_args).stdout(Stdio::piped()).stderr(Stdio::piped());
    let mut child = command.spawn().map_err(|error| error.to_string())?;
    let pid = child.id();
    let stdout = child.stdout.take();
    let stderr = child.stderr.take();
    let app_stdout = app.clone();
    let app_stderr = app.clone();
    let app_exit = app.clone();
    let source_stdout = source.to_string();
    let source_stderr = source.to_string();
    let source_exit = source.to_string();
    let on_line_arc = on_line.map(Arc::new);

    if let Some(stdout) = stdout {
        let on_line_arc = on_line_arc.clone();
        std::thread::spawn(move || {
            let reader = BufReader::new(stdout);
            for line in reader.lines().map_while(Result::ok) {
                let entry = make_log(&source_stdout, "stdout", line.clone());
                let _ = app_stdout.emit("event:log", &entry);
                if let Some(handler) = &on_line_arc {
                    handler(&line, false);
                }
            }
        });
    }
    if let Some(stderr) = stderr {
        let on_line_arc = on_line_arc.clone();
        std::thread::spawn(move || {
            let reader = BufReader::new(stderr);
            for line in reader.lines().map_while(Result::ok) {
                let entry = make_log(&source_stderr, "stderr", line.clone());
                let _ = app_stderr.emit("event:log", &entry);
                if let Some(handler) = &on_line_arc {
                    handler(&line, true);
                }
            }
        });
    }
    std::thread::spawn(move || {
        let status = child.wait();
        let (code, error) = match status {
            Ok(status) => (status.code(), None),
            Err(error) => (None, Some(error.to_string())),
        };
        let entry = make_log(&source_exit, if code == Some(0) { "success" } else { "error" }, format!("进程退出（exit {:?}）", code));
        let _ = app_exit.emit("event:log", &entry);
        on_exit(code, error);
    });
    Ok(pid)
}

// MARK: - Web 服务

pub struct WebService {
    pub state: Arc<Mutex<WebServerState>>,
    child: Mutex<Option<u32>>,
    user_stop: Arc<AtomicBool>,
}

impl WebService {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(WebServerState::Stopped)),
            child: Mutex::new(None),
            user_stop: Arc::new(AtomicBool::new(false)),
        }
    }

    pub fn current(&self) -> WebServerState {
        self.state.lock().map(|s| s.clone()).unwrap_or(WebServerState::Stopped)
    }

    pub fn start(&self, app: &AppHandle, env_service: &EnvironmentService, settings: &AppSettingsData) -> bool {
        let current = self.current();
        if matches!(current, WebServerState::Starting | WebServerState::Running { .. }) {
            return false;
        }
        if self.child.lock().ok().and_then(|c| *c).is_some() {
            return false;
        }
        self.user_stop.store(false, Ordering::SeqCst);
        {
            let mut state = self.state.lock().unwrap();
            *state = WebServerState::Starting;
        }
        let _ = app.emit("event:web-state", self.current());

        let (program, args) = if let Some(dsh) = env_service.dsh_path() {
            (dsh, vec!["web".to_string(), "--host".into(), "127.0.0.1".into(), "--port".into(), settings.web_port.to_string()])
        } else if let Some(npm) = env_service.npm_path() {
            (
                npm,
                vec![
                    "exec".into(), "--yes".into(), "--package=@deepseek-ai/dsh".into(), "--".into(),
                    "dsh".into(), "web".into(), "--host".into(), "127.0.0.1".into(),
                    "--port".into(), settings.web_port.to_string(),
                ],
            )
        } else {
            let mut state = self.state.lock().unwrap();
            *state = WebServerState::Failed { error: "运行环境未就绪：需要 dsh 或 Node.js/npm".into() };
            let _ = app.emit("event:web-state", self.current());
            return false;
        };

        let mut spawn_env = env_service.spawn_environment.clone();
        if !settings.dsh_home.trim().is_empty() {
            spawn_env.insert("DSH_HOME".into(), expand_tilde(settings.dsh_home.trim()));
        }
        if !settings.api_key.trim().is_empty() {
            spawn_env.insert("DEEPSEEK_API_KEY".into(), settings.api_key.trim().to_string());
        }
        if settings.telemetry_disabled {
            spawn_env.insert("DSH_TELEMETRY_DISABLED".into(), "1".into());
        }

        emit_log(app, "web", "info", "正在启动 DeepSeek Harness Web UI…");
        emit_log(app, "web", "command", format!("{program} {}", args.join(" ")));

        let state_clone = self.state.clone();
        let user_stop = self.user_stop.clone();
        let state_emit = self.state.clone();
        let app_line = app.clone();
        let app_exit = app.clone();
        match spawn_streaming_with_lines(
            app,
            "web",
            program,
            args,
            Some(&spawn_env),
            move |line, stderr| {
                if stderr {
                    return;
                }
                if let Some(url) = parse_web_url(line) {
                    let mut state = state_clone.lock().unwrap();
                    if matches!(*state, WebServerState::Starting) {
                        *state = WebServerState::Running { url: url.clone() };
                        let _ = app_line.emit("event:web-state", state.clone());
                        emit_log(&app_line, "web", "success", format!("Web UI 已就绪：{url}"));
                    }
                }
            },
            move |code, error| {
                let mut state = state_emit.lock().unwrap();
                if user_stop.load(Ordering::SeqCst) {
                    *state = WebServerState::Stopped;
                } else {
                    *state = WebServerState::Failed {
                        error: error.unwrap_or_else(|| format!("进程已退出（exit {:?}）", code)),
                    };
                }
                let _ = app_exit.emit("event:web-state", state.clone());
            },
        ) {
            Ok(pid) => {
                *self.child.lock().unwrap() = Some(pid);
                true
            }
            Err(error) => {
                let mut state = self.state.lock().unwrap();
                *state = WebServerState::Failed { error };
                let _ = app.emit("event:web-state", self.current());
                false
            }
        }
    }

    pub fn stop(&self, app: &AppHandle) {
        self.user_stop.store(true, Ordering::SeqCst);
        if let Some(pid) = self.child.lock().unwrap().take() {
            kill_pid(pid);
        }
        {
            let mut state = self.state.lock().unwrap();
            *state = WebServerState::Stopped;
            let _ = app.emit("event:web-state", state.clone());
        }
        emit_log(app, "web", "info", "Web 服务已停止");
    }
}

pub fn parse_web_url(line: &str) -> Option<String> {
    for marker in ["http://127.0.0.1:", "http://localhost:", "https://127.0.0.1:"] {
        if let Some(index) = line.find(marker) {
            let rest = &line[index..];
            let body = rest.strip_prefix("http://").or_else(|| rest.strip_prefix("https://")).unwrap_or(rest);
            let host_end = body.find('/').unwrap_or(body.len());
            let host_port = &body[..host_end];
            if let Some((host, port)) = host_port.rsplit_once(':') {
                let port_digits: String = port.chars().take_while(|c| c.is_ascii_digit()).collect();
                if (2..=5).contains(&port_digits.len()) && (host == "127.0.0.1" || host == "localhost") {
                    let scheme = if rest.starts_with("https") { "https" } else { "http" };
                    return Some(format!("{scheme}://{host_port}"));
                }
            }
        }
    }
    None
}

// MARK: - 插件服务

pub struct PluginService {
    pub installed: Arc<Mutex<Vec<InstalledPlugin>>>,
    pub profiles: Arc<Mutex<Vec<String>>>,
    pub profile_name: Arc<Mutex<String>>,
    pub is_working: Arc<AtomicBool>,
    profile_dir_cache: Arc<Mutex<String>>,
}

impl PluginService {
    pub fn new(profile_name: String) -> Self {
        Self {
            installed: Arc::new(Mutex::new(Vec::new())),
            profiles: Arc::new(Mutex::new(vec!["web".into()])),
            profile_name: Arc::new(Mutex::new(profile_name)),
            is_working: Arc::new(AtomicBool::new(false)),
            profile_dir_cache: Arc::new(Mutex::new(String::new())),
        }
    }

    pub fn profile_dir(&self, settings: &AppSettingsData) -> String {
        let profile = self.profile_name.lock().unwrap().clone();
        let path = format!("{}/profiles/{profile}", dsh_home_directory(settings));
        *self.profile_dir_cache.lock().unwrap() = path.clone();
        path
    }

    pub fn refresh(&self, app: &AppHandle, settings: &AppSettingsData) {
        let root = format!("{}/profiles", dsh_home_directory(settings));
        let mut names: Vec<String> = Vec::new();
        if let Ok(entries) = fs::read_dir(&root) {
            for entry in entries.flatten() {
                if entry.path().join("package.json").exists() {
                    if let Some(name) = entry.file_name().to_str() {
                        names.push(name.to_string());
                    }
                }
            }
        }
        names.sort();
        if !names.contains(&"web".to_string()) {
            names.insert(0, "web".into());
        }
        let mut profile = self.profile_name.lock().unwrap();
        if !names.contains(&profile) {
            *profile = names.first().cloned().unwrap_or_else(|| "web".into());
        }
        drop(profile);
        *self.profiles.lock().unwrap() = names.clone();
        let _ = app.emit("event:profiles", names);
        self.load_installed(app, settings);
    }

    pub fn set_profile(&self, app: &AppHandle, settings: &AppSettingsData, name: String) {
        let trimmed = if name.trim().is_empty() { "web".to_string() } else { name.trim().to_string() };
        *self.profile_name.lock().unwrap() = trimmed;
        self.load_installed(app, settings);
    }

    pub fn load_installed(&self, app: &AppHandle, settings: &AppSettingsData) {
        let manifest_path = format!("{}/package.json", self.profile_dir(settings));
        let mut installed: Vec<InstalledPlugin> = Vec::new();
        if let Ok(raw) = fs::read_to_string(&manifest_path) {
            if let Ok(manifest) = serde_json::from_str::<serde_json::Value>(&raw) {
                let dependencies = manifest.get("dependencies").and_then(|v| v.as_object());
                let bundles = manifest.pointer("/dsh/profile/bundles").and_then(|v| v.as_array());
                let bundle_names: Vec<String> = bundles.map(|items| items.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect()).unwrap_or_default();
                if let Some(dependencies) = dependencies {
                    let mut names: Vec<&String> = dependencies.keys().collect();
                    names.sort();
                    for name in names {
                        let spec = dependencies.get(name).and_then(|v| v.as_str()).unwrap_or("").to_string();
                        let is_bundle = bundle_names.contains(name);
                        installed.push(self.describe(name.clone(), spec, is_bundle, false));
                    }
                }
                for name in &bundle_names {
                    if !dependencies.map(|deps| deps.contains_key(name)).unwrap_or(false) {
                        installed.push(self.describe(name.clone(), "dsh 随附 bundle".into(), true, true));
                    }
                }
            }
        } else {
            for name in ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"] {
                installed.push(self.describe(name.into(), "dsh 随附 bundle".into(), true, true));
            }
        }
        installed.sort_by(|a, b| match (a.is_inbox, b.is_inbox) {
            (true, false) => std::cmp::Ordering::Greater,
            (false, true) => std::cmp::Ordering::Less,
            _ => a.name.cmp(&b.name),
        });
        *self.installed.lock().unwrap() = installed.clone();
        let _ = app.emit("event:plugins", installed);
    }

    fn describe(&self, name: String, spec: String, is_bundle: bool, is_inbox: bool) -> InstalledPlugin {
        InstalledPlugin {
            version: self.installed_version(&name),
            source_kind: source_kind(&spec).to_string(),
            local_source: local_source(&spec),
            external_url: external_url(&name, &spec),
            name,
            spec,
            is_bundle,
            is_inbox,
        }
    }

    fn installed_version(&self, name: &str) -> Option<String> {
        let root = self.profile_dir_cache.lock().unwrap().clone();
        let mut candidates = vec![format!("{root}/node_modules/{name}/package.json")];
        let pnpm_store = format!("{root}/node_modules/.pnpm");
        if let Ok(entries) = fs::read_dir(&pnpm_store) {
            let mut matching: Vec<_> = entries.flatten().filter(|e| e.file_name().to_string_lossy().starts_with(&format!("{name}@"))).collect();
            matching.sort_by(|a, b| b.file_name().cmp(&a.file_name()));
            for entry in matching.into_iter().take(6) {
                candidates.push(format!("{}/node_modules/{name}/package.json", entry.path().to_string_lossy()));
            }
        }
        for candidate in candidates.into_iter().take(12) {
            if let Ok(raw) = fs::read_to_string(candidate) {
                if let Ok(manifest) = serde_json::from_str::<serde_json::Value>(&raw) {
                    if let Some(version) = manifest.get("version").and_then(|v| v.as_str()) {
                        return Some(version.to_string());
                    }
                }
            }
        }
        None
    }

    pub fn install_github(&self, app: AppHandle, input: String, env_service: &EnvironmentService, settings: &AppSettingsData) -> Result<(), String> {
        let spec = parse_github_spec(&input)?;
        self.run_plugin(&app, &["add".into(), spec.pnpm], &format!("安装 {}", spec.display), env_service, settings)
    }

    pub fn install_npm(&self, app: AppHandle, input: String, env_service: &EnvironmentService, settings: &AppSettingsData) -> Result<(), String> {
        let spec = input.trim().to_string();
        if spec.is_empty() {
            return Err("请输入 npm 包名".into());
        }
        self.run_plugin(&app, &["add".into(), spec.clone()], &format!("安装 {spec}"), env_service, settings)
    }

    pub fn install_folder(&self, app: AppHandle, folder: String, label: Option<String>, env_service: &EnvironmentService, settings: &AppSettingsData) -> Result<(), String> {
        if !Path::new(&folder).join("package.json").exists() {
            return Err("所选文件夹中必须包含 package.json".into());
        }
        let spec = format!("file://{}", folder);
        self.run_plugin(&app, &["add".into(), spec], &format!("安装 {}", label.unwrap_or_else(|| folder.clone())), env_service, settings)
    }

    pub fn install_zip(&self, app: AppHandle, archive: String, env_service: &EnvironmentService, settings: &AppSettingsData) -> Result<(), String> {
        let staging = app.path().temp_dir().map(|p| p.join(format!("dsh-plugin-{}", std::process::id()))).map_err(|e| e.to_string())?;
        let _ = fs::remove_dir_all(&staging);
        fs::create_dir_all(&staging).map_err(|e| e.to_string())?;
        let result = (|| -> Result<(), String> {
            let file = fs::File::open(&archive).map_err(|e| e.to_string())?;
            let mut zip = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
            zip.extract(&staging).map_err(|e| e.to_string())?;
            let entries = walk_files(&staging);
            let root = locate_package_root(&entries).ok_or_else(|| "压缩包内没有找到 package.json（需位于根目录或唯一顶层文件夹内）".to_string())?;
            let package_root = staging.join(root);
            let mut package_name = format!("plugin-{}", std::process::id());
            if let Ok(raw) = fs::read_to_string(package_root.join("package.json")) {
                if let Ok(manifest) = serde_json::from_str::<serde_json::Value>(&raw) {
                    if let Some(name) = manifest.get("name").and_then(|v| v.as_str()) {
                        package_name = name.replace('/', "_");
                    }
                }
            }
            let sources_root = app.path().app_data_dir().map(|p| p.join("PluginSources")).map_err(|e| e.to_string())?;
            fs::create_dir_all(&sources_root).map_err(|e| e.to_string())?;
            let destination = sources_root.join(&package_name);
            let _ = fs::remove_dir_all(&destination);
            fs::rename(&package_root, &destination).map_err(|e| e.to_string())?;
            let spec = format!("file://{}", destination.to_string_lossy());
            self.run_plugin(&app, &["add".into(), spec], &format!("安装 {}", archive), env_service, settings)
        })();
        let _ = fs::remove_dir_all(&staging);
        result
    }

    pub fn update(&self, app: AppHandle, name: String, env_service: &EnvironmentService, settings: &AppSettingsData) -> Result<(), String> {
        let plugin = self.installed.lock().unwrap().iter().find(|p| p.name == name).cloned().ok_or_else(|| "未找到该插件".to_string())?;
        if plugin.is_inbox {
            return Err("内置 bundle 随 dsh 一起升级".into());
        }
        let args = if plugin.source_kind == "npm" {
            vec!["update".into(), "--latest".into(), name.clone()]
        } else {
            vec!["update".into(), name.clone()]
        };
        self.run_plugin(&app, &args, &format!("更新 {name}"), env_service, settings)
    }

    pub fn remove(&self, app: AppHandle, name: String, env_service: &EnvironmentService, settings: &AppSettingsData) -> Result<(), String> {
        let plugin = self.installed.lock().unwrap().iter().find(|p| p.name == name).cloned().ok_or_else(|| "未找到该插件".to_string())?;
        if plugin.is_inbox {
            return Err("内置 bundle 由 dsh 随附，不能移除".into());
        }
        self.run_plugin(&app, &["remove".into(), name.clone()], &format!("移除 {name}"), env_service, settings)
    }

    fn run_plugin(&self, app: &AppHandle, args: &[String], label: &str, env_service: &EnvironmentService, settings: &AppSettingsData) -> Result<(), String> {
        let dsh = env_service.dsh_path().ok_or_else(|| "缺少 dsh，请先配置运行环境".to_string())?;
        if env_service.pnpm_path().is_none() {
            return Err("pnpm 不可用".into());
        }
        self.is_working.store(true, Ordering::SeqCst);
        let mut full_args = vec!["plugin".into(), "--profile".into(), self.profile_name.lock().unwrap().clone()];
        full_args.extend(args.iter().cloned());
        let mut env = env_service.spawn_environment.clone();
        if !settings.dsh_home.trim().is_empty() {
            env.insert("DSH_HOME".into(), expand_tilde(settings.dsh_home.trim()));
        }
        emit_log(app, "plugins", "command", format!("dsh {label}: {}", full_args.join(" ")));
        let (tx, rx) = mpsc::channel();
        let result = spawn_streaming_owned(app, "plugins", dsh, full_args, Some(&env), move |code, error| {
            let _ = tx.send((code, error));
        });
        match result {
            Ok(_pid) => {
                let (code, _error) = rx.recv().unwrap_or((None, None));
                self.is_working.store(false, Ordering::SeqCst);
                if code == Some(0) {
                    emit_log(app, "plugins", "success", format!("{label} 完成"));
                    self.load_installed(app, settings);
                    Ok(())
                } else {
                    Err(format!("命令失败（exit {:?}），请查看运行日志", code))
                }
            }
            Err(error) => {
                self.is_working.store(false, Ordering::SeqCst);
                Err(error)
            }
        }
    }
}

pub fn parse_github_spec(input: &str) -> Result<GitHubSpec, String> {
    let input = input.trim();
    if input.is_empty() {
        return Err("请输入 GitHub 仓库地址".into());
    }
    let normalized = input
        .replace("git+ssh://git@github.com/", "https://github.com/")
        .replace("ssh://git@github.com/", "https://github.com/")
        .replace("git@github.com:", "https://github.com/")
        .replace("git+https://github.com/", "https://github.com/");
    if normalized.contains("github.com") {
        let without = normalized.replace("https://github.com/", "").replace("http://github.com/", "");
        let path_part = without.split('#').next().unwrap_or("");
        let pieces: Vec<String> = path_part.split('/').filter(|p| !p.is_empty()).map(|p| p.to_string()).collect();
        if pieces.len() < 2 {
            return Err("无法解析 GitHub 仓库".into());
        }
        if pieces.len() > 2 && !(pieces.len() >= 4 && pieces[2].eq_ignore_ascii_case("tree")) {
            return Err("不支持的地址：仅支持 owner/repo 形式".into());
        }
        let owner = pieces[0].clone();
        let repo = strip_git_suffix(&pieces[1]);
        let mut reference = normalized.split('#').nth(1).map(|s| s.to_string());
        if pieces.len() >= 4 && pieces[2].eq_ignore_ascii_case("tree") {
            reference = Some(pieces[3..].join("/"));
        }
        return build_spec(owner, repo, reference, input);
    }
    if input.contains('/') {
        let (path_part, fragment) = input.split_once('#').unwrap_or((input, ""));
        let pieces: Vec<String> = path_part.replace("github:", "").split('/').filter(|p| !p.is_empty()).map(|p| p.to_string()).collect();
        if pieces.len() != 2 {
            return Err("不支持的地址：仅支持 owner/repo 形式".into());
        }
        return build_spec(pieces[0].clone(), strip_git_suffix(&pieces[1]), if fragment.is_empty() { None } else { Some(fragment.to_string()) }, input);
    }
    Err("不支持的地址：请输入 owner/repo 或 GitHub URL".into())
}

pub struct GitHubSpec {
    pub display: String,
    pub pnpm: String,
}

fn build_spec(owner: String, repo: String, reference: Option<String>, input: &str) -> Result<GitHubSpec, String> {
    let valid = |name: &str| !name.is_empty() && name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-'));
    if !valid(&owner) || !valid(&repo) {
        return Err(format!("无法解析 GitHub 仓库：{input}"));
    }
    let reference = reference.map(|r| r.trim().to_string()).filter(|r| !r.is_empty());
    let pnpm = match &reference {
        Some(reference) => format!("github:{owner}/{repo}#{reference}"),
        None => format!("github:{owner}/{repo}"),
    };
    let display = match &reference {
        Some(reference) => format!("{owner}/{repo}@{reference}"),
        None => format!("{owner}/{repo}"),
    };
    Ok(GitHubSpec { display, pnpm })
}

fn strip_git_suffix(name: &str) -> String {
    if name.to_ascii_lowercase().ends_with(".git") {
        name[..name.len() - 4].to_string()
    } else {
        name.to_string()
    }
}

fn source_kind(spec: &str) -> &'static str {
    let lower = spec.to_ascii_lowercase();
    if lower.starts_with("file:") || lower.starts_with("link:") {
        "folder"
    } else if lower.contains("github:") || lower.contains("git+") || lower.contains("git@") {
        "github"
    } else if lower.starts_with("http") && lower.contains(".tgz") {
        "zip"
    } else {
        "npm"
    }
}

fn local_source(spec: &str) -> Option<String> {
    let lower = spec.to_ascii_lowercase();
    if !lower.starts_with("file:") && !lower.starts_with("link:") {
        return None;
    }
    spec.strip_prefix("file:").or_else(|| spec.strip_prefix("link:")).map(|p| p.trim_start_matches("//").to_string())
}

fn external_url(name: &str, spec: &str) -> Option<String> {
    match source_kind(spec) {
        "npm" => Some(format!("https://www.npmjs.com/package/{name}")),
        "github" => {
            let cleaned = spec.replace("github:", "https://github.com/");
            let url = url::Url::parse(&cleaned).ok()?;
            let pieces: Vec<String> = url.path().split('/').filter(|p| !p.is_empty()).map(|p| p.to_string()).collect();
            if pieces.len() < 2 {
                return None;
            }
            let repo = strip_git_suffix(&pieces[1]);
            let base = format!("https://github.com/{}/{}", pieces[0], repo);
            Some(match url.fragment() {
                Some(reference) if !reference.is_empty() => format!("{base}/tree/{reference}"),
                _ => base,
            })
        }
        _ => None,
    }
}

fn walk_files(root: &Path) -> Vec<String> {
    let mut result = Vec::new();
    let prefix = root.to_string_lossy().to_string();
    let prefix = prefix.trim_end_matches('/').to_string();
    fn visit(dir: &Path, prefix: &str, result: &mut Vec<String>) {
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    let name = entry.file_name();
                    if name != "__MACOSX" && !name.to_string_lossy().starts_with('.') {
                        visit(&path, prefix, result);
                    }
                } else if let Ok(relative) = path.strip_prefix(prefix) {
                    result.push(relative.to_string_lossy().replace('\\', "/"));
                }
            }
        }
    }
    visit(root, &prefix, &mut result);
    result
}

fn locate_package_root(entries: &[String]) -> Option<String> {
    let normalized: Vec<&str> = entries.iter().map(|entry| entry.trim_start_matches('/')).filter(|entry| !entry.is_empty() && !entry.starts_with("__MACOSX")).collect();
    if normalized.iter().any(|entry| *entry == "package.json") {
        return Some(String::new());
    }
    let mut top: Vec<&str> = Vec::new();
    for entry in &normalized {
        if let Some((first, _)) = entry.split_once('/') {
            if !top.contains(&first) {
                top.push(first);
            }
        }
    }
    if top.len() == 1 && normalized.iter().any(|entry| *entry == format!("{}/package.json", top[0])) {
        return Some(top[0].to_string());
    }
    None
}

// MARK: - 会话服务

pub struct SessionService {
    pub sessions: Arc<Mutex<Vec<SessionSummary>>>,
    stamps: Mutex<HashMap<String, (u64, u64)>>,
    metadata: Mutex<HashMap<String, SessionMetadata>>,
    pub is_syncing: Arc<AtomicBool>,
    last_attempt: Mutex<u64>,
}

#[derive(Clone)]
struct SessionMetadata {
    id: Option<String>,
    workspace: Option<String>,
    created_at: Option<u64>,
    title: Option<String>,
}

impl SessionService {
    pub fn new() -> Self {
        Self {
            sessions: Arc::new(Mutex::new(Vec::new())),
            stamps: Mutex::new(HashMap::new()),
            metadata: Mutex::new(HashMap::new()),
            is_syncing: Arc::new(AtomicBool::new(false)),
            last_attempt: Mutex::new(0),
        }
    }

    pub fn sessions_root(&self, settings: &AppSettingsData) -> String {
        format!("{}/sessions", dsh_home_directory(settings))
    }

    pub fn sync(&self, app: &AppHandle, settings: &AppSettingsData, env_service: &EnvironmentService, force: bool) {
        if self.is_syncing.swap(true, Ordering::SeqCst) {
            return;
        }
        let now = now_ms();
        let mut last = self.last_attempt.lock().unwrap();
        if !force && now.saturating_sub(*last) < 5000 {
            self.is_syncing.store(false, Ordering::SeqCst);
            return;
        }
        *last = now;
        drop(last);

        let root = self.sessions_root(settings);
        let scanned = scan_sessions(&root);
        let current: Vec<String> = scanned.iter().map(|s| s.path.clone()).collect();
        let mut stamps = self.stamps.lock().unwrap();
        let mut metadata = self.metadata.lock().unwrap();
        stamps.retain(|path, _| current.contains(path));
        metadata.retain(|path, _| current.contains(path));

        let to_read: Vec<ScannedSession> = scanned
            .iter()
            .filter(|item| stamps.get(&item.path).map(|stamp| *stamp != item.stamp).unwrap_or(true))
            .take(120)
            .cloned()
            .collect();
        if !to_read.is_empty() {
            emit_log(app, "sessions", "info", format!("发现 {} 个新增/变化的本地会话，正在读取元数据…", to_read.len()));
        }
        for item in &to_read {
            stamps.insert(item.path.clone(), item.stamp);
            metadata.insert(item.path.clone(), read_session_metadata(&item.path, &item.directory, env_service));
        }

        let mut sessions: Vec<SessionSummary> = scanned
            .iter()
            .map(|item| {
                let meta = metadata.get(&item.path).cloned().unwrap_or(SessionMetadata { id: None, workspace: None, created_at: None, title: None });
                let project = Path::new(&item.path).parent().and_then(|p| p.parent()).and_then(|p| p.file_name()).map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
                let title = meta.title.clone().filter(|t| !t.trim().is_empty()).or(Some(item.directory.clone()));
                SessionSummary {
                    id: meta.id.clone().unwrap_or_else(|| item.directory.clone()),
                    directory_name: item.directory.clone(),
                    project_name: project,
                    workspace_path: meta.workspace.clone(),
                    title: title.clone(),
                    display_title: title.unwrap_or_default(),
                    created_at: meta.created_at,
                    updated_at: Some(item.stamp.0),
                    file_path: item.path.clone(),
                }
            })
            .collect();
        sessions.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
        *self.sessions.lock().unwrap() = sessions.clone();
        emit_log(app, "sessions", "success", format!("历史会话已同步：{} 个（目录 {root}）", sessions.len()));
        let _ = app.emit("event:sessions", sessions);
        self.is_syncing.store(false, Ordering::SeqCst);
    }
}

#[derive(Clone)]
struct ScannedSession {
    directory: String,
    path: String,
    stamp: (u64, u64),
}

fn scan_sessions(root: &str) -> Vec<ScannedSession> {
    let mut result = Vec::new();
    let Ok(projects) = fs::read_dir(root) else { return result };
    for project in projects.flatten() {
        if !project.path().is_dir() {
            continue;
        }
        let Ok(sessions) = fs::read_dir(project.path()) else { continue };
        for session in sessions.flatten() {
            if !session.path().is_dir() {
                continue;
            }
            for candidate in ["session.jsonl.zstd", "session.jsonl"] {
                let path = session.path().join(candidate);
                if let Ok(meta) = fs::metadata(&path) {
                    if meta.is_file() {
                        let modified = meta.modified().ok().and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok()).map(|d| d.as_millis() as u64).unwrap_or(0);
                        result.push(ScannedSession {
                            directory: session.file_name().to_string_lossy().to_string(),
                            path: path.to_string_lossy().to_string(),
                            stamp: (modified, meta.len()),
                        });
                        break;
                    }
                }
            }
        }
    }
    result.sort_by(|a, b| b.stamp.0.cmp(&a.stamp.0));
    result
}

fn read_session_metadata(path: &str, fallback: &str, env_service: &EnvironmentService) -> SessionMetadata {
    let empty = SessionMetadata { id: None, workspace: None, created_at: None, title: None };
    if !path.ends_with(".jsonl") {
        if let Some(zstd) = find_executable("zstd", &env_service.tools.known_bin_directories) {
            if let Some(meta) = read_metadata_via_zstd(&zstd, path) {
                return meta;
            }
        }
        return SessionMetadata { id: None, workspace: None, created_at: None, title: Some(fallback.to_string()) };
    }
    if let Ok(raw) = fs::read_to_string(path) {
        return parse_metadata_lines(raw.lines(), fallback);
    }
    empty
}

fn read_metadata_via_zstd(zstd: &str, path: &str) -> Option<SessionMetadata> {
    let (mut command, args) = base_command(zstd, &["-dc".into(), path.into()], None);
    command.args(&args).stdout(Stdio::piped()).stderr(Stdio::null());
    let mut child = command.spawn().ok()?;
    let stdout = child.stdout.take()?;
    let reader = BufReader::new(stdout);
    let mut state = SessionMetadata { id: None, workspace: None, created_at: None, title: None };
    let mut lines = 0;
    for line in reader.lines().map_while(Result::ok) {
        lines += 1;
        if lines > 1500 {
            break;
        }
        parse_metadata_line(&line, &mut state);
        if state.id.is_some() && state.title.is_some() {
            break;
        }
    }
    let _ = child.kill();
    let _ = child.wait();
    if state.id.is_some() || state.title.is_some() {
        Some(state)
    } else {
        None
    }
}

fn parse_metadata_lines<'a>(lines: impl Iterator<Item = &'a str>, fallback: &str) -> SessionMetadata {
    let mut state = SessionMetadata { id: None, workspace: None, created_at: None, title: None };
    for (index, line) in lines.enumerate() {
        if index >= 1500 {
            break;
        }
        parse_metadata_line(line, &mut state);
        if state.id.is_some() && state.title.is_some() {
            break;
        }
    }
    if state.title.is_none() {
        state.title = Some(fallback.to_string());
    }
    state
}

fn parse_metadata_line(line: &str, state: &mut SessionMetadata) {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(line) else { return };
    let Some(object) = value.as_object() else { return };
    if state.id.is_none() && object.get("type").and_then(|v| v.as_str()) == Some("session") {
        if let Some(id) = object.get("id").and_then(|v| v.as_str()) {
            state.id = Some(id.to_string());
        }
        state.created_at = object.get("createdAt").and_then(|v| v.as_f64()).map(|ms| if ms > 10_000_000_000.0 { ms as u64 } else { (ms * 1000.0) as u64 });
        state.workspace = object.get("cwd").and_then(|v| v.as_str()).map(|s| s.to_string());
    }
    if state.title.is_none() && object.get("type").and_then(|v| v.as_str()) == Some("session/title") {
        if let Some(title) = object.get("data").and_then(|d| d.get("title")).and_then(|v| v.as_str()) {
            let title = title.trim();
            if !title.is_empty() {
                state.title = Some(title.chars().take(160).collect());
            }
        }
    }
}

// MARK: - 应用状态

pub struct AppState {
    pub settings: Mutex<SettingsService>,
    pub environment: Mutex<EnvironmentService>,
    pub web: WebService,
    pub plugins: PluginService,
    pub sessions: SessionService,
    pub logs: Mutex<LogStore>,
}

impl AppState {
    pub fn new(settings: SettingsService) -> Self {
        let profile = settings.data.profile_name.clone();
        Self {
            settings: Mutex::new(settings),
            environment: Mutex::new(EnvironmentService::new()),
            web: WebService::new(),
            plugins: PluginService::new(profile),
            sessions: SessionService::new(),
            logs: Mutex::new(LogStore::new()),
        }
    }
}

pub fn kill_pid(pid: u32) {
    #[cfg(target_os = "windows")]
    let _ = Command::new("taskkill").args(["/PID", &pid.to_string(), "/T", "/F"]).spawn();
    #[cfg(not(target_os = "windows"))]
    let _ = Command::new("kill").arg(pid.to_string()).spawn();
}
