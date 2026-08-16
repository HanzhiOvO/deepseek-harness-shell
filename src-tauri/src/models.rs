use serde::{Deserialize, Serialize};

#[derive(Clone, Serialize, Deserialize, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct AppSettingsData {
    pub auto_start_web: bool,
    pub auto_install_dsh: bool,
    pub stop_when_closed: bool,
    pub telemetry_disabled: bool,
    pub web_port: u32,
    pub profile_name: String,
    pub api_key: String,
    pub custom_dsh_path: String,
    pub dsh_home: String,
    pub appearance: String,
    pub pinned_session_ids: Vec<String>,
}

impl Default for AppSettingsData {
    fn default() -> Self {
        Self {
            auto_start_web: true,
            auto_install_dsh: true,
            stop_when_closed: true,
            telemetry_disabled: true,
            web_port: 0,
            profile_name: "web".into(),
            api_key: String::new(),
            custom_dsh_path: String::new(),
            dsh_home: String::new(),
            appearance: "system".into(),
            pinned_session_ids: Vec::new(),
        }
    }
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ToolInfo {
    pub name: String,
    pub path: String,
    pub version: Option<String>,
}

#[derive(Clone, Serialize, Debug, Default)]
#[serde(rename_all = "camelCase")]
pub struct Toolchain {
    pub dsh: Option<ToolInfo>,
    pub node: Option<ToolInfo>,
    pub npm: Option<ToolInfo>,
    pub pnpm: Option<ToolInfo>,
    pub git: Option<ToolInfo>,
    pub brew: Option<ToolInfo>,
    pub known_bin_directories: Vec<String>,
}

#[derive(Clone, Serialize, Debug)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum EnvironmentState {
    Idle {
        label: String,
        can_install: bool,
        detail: String,
    },
    Checking {
        label: String,
        can_install: bool,
        detail: String,
    },
    Ready {
        label: String,
        can_install: bool,
        detail: String,
    },
    MissingDsh {
        label: String,
        can_install: bool,
        detail: String,
    },
    MissingNode {
        label: String,
        can_install: bool,
        detail: String,
    },
    MissingNpm {
        label: String,
        can_install: bool,
        detail: String,
    },
    Installing {
        label: String,
        can_install: bool,
        detail: String,
    },
    Failed {
        label: String,
        can_install: bool,
        detail: String,
    },
}

#[derive(Clone, Serialize, Debug)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum WebServerState {
    Stopped,
    Starting,
    Running { url: String },
    Failed { error: String },
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct LogEntry {
    pub id: String,
    pub date: u64,
    pub source: String,
    pub level: String,
    pub text: String,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct InstalledPlugin {
    pub name: String,
    pub spec: String,
    pub version: Option<String>,
    pub is_bundle: bool,
    pub is_inbox: bool,
    pub source_kind: String,
    pub local_source: Option<String>,
    pub external_url: Option<String>,
}

#[derive(Clone, Serialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct SessionSummary {
    pub id: String,
    pub directory_name: String,
    pub project_name: String,
    pub workspace_path: Option<String>,
    pub title: Option<String>,
    pub display_title: String,
    pub created_at: Option<u64>,
    pub updated_at: Option<u64>,
    pub file_path: String,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct BootstrapPayload {
    pub platform: String,
    pub version: String,
    pub data_dirs: DataDirs,
    pub settings: AppSettingsData,
    pub environment: EnvironmentPayload,
    pub web: WebServerState,
    pub sessions: Vec<SessionSummary>,
    pub plugins: Vec<InstalledPlugin>,
    pub profiles: Vec<String>,
    pub profile_name: String,
    pub logs: serde_json::Value,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct DataDirs {
    pub dsh_home: String,
    pub profile_directory: String,
    pub settings_directory: String,
    pub plugin_sources_directory: String,
}

#[derive(Serialize, Clone, Debug)]
#[serde(rename_all = "camelCase")]
pub struct EnvironmentPayload {
    pub state: EnvironmentState,
    pub tools: Toolchain,
    pub is_working: bool,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct InstallDraft {
    pub kind: String,
    pub github_text: Option<String>,
    pub npm_text: Option<String>,
    pub file_path: Option<String>,
}

#[derive(Deserialize, Debug)]
#[serde(rename_all = "camelCase")]
pub struct OpenSessionRequest {
    pub id: String,
    pub display_title: String,
}
