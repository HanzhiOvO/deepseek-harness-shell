export type ViewId = 'chat' | 'history' | 'plugins' | 'logs' | 'settings'

export type AppearanceMode = 'system' | 'light' | 'dark'

export interface AppSettingsData {
  autoStartWeb: boolean
  autoInstallDsh: boolean
  stopWhenClosed: boolean
  telemetryDisabled: boolean
  webPort: number
  profileName: string
  apiKey: string
  customDshPath: string
  dshHome: string
  appearance: AppearanceMode
  pinnedSessionIds: string[]
}

export interface ToolInfo {
  name: string
  path: string
  version: string | null
}

export interface Toolchain {
  dsh: ToolInfo | null
  node: ToolInfo | null
  npm: ToolInfo | null
  pnpm: ToolInfo | null
  git: ToolInfo | null
  brew: ToolInfo | null
  knownBinDirectories: string[]
}

export type EnvironmentState =
  | { kind: 'idle'; label: string; canInstall: boolean; detail: string }
  | { kind: 'checking'; label: string; canInstall: boolean; detail: string }
  | { kind: 'ready'; label: string; canInstall: boolean; detail: string }
  | { kind: 'missing-dsh'; label: string; canInstall: boolean; detail: string }
  | { kind: 'missing-node'; label: string; canInstall: boolean; detail: string }
  | { kind: 'missing-npm'; label: string; canInstall: boolean; detail: string }
  | { kind: 'installing'; label: string; canInstall: boolean; detail: string }
  | { kind: 'failed'; label: string; canInstall: boolean; detail: string }

export type WebServerState =
  | { kind: 'stopped' }
  | { kind: 'starting' }
  | { kind: 'running'; url: string }
  | { kind: 'failed'; error: string }

export type LogLevel = 'info' | 'command' | 'stdout' | 'stderr' | 'warning' | 'error' | 'success'
export type LogSource = 'environment' | 'web' | 'plugins' | 'sessions'

export interface LogEntry {
  id: string
  date: number
  source: LogSource
  level: LogLevel
  text: string
}

export type PluginSourceKind = 'github' | 'zip' | 'folder' | 'npm'

export interface InstalledPlugin {
  name: string
  spec: string
  version: string | null
  isBundle: boolean
  isInbox: boolean
  sourceKind: PluginSourceKind
  localSource: string | null
  externalUrl: string | null
}

export interface SessionSummary {
  id: string
  directoryName: string
  projectName: string
  workspacePath: string | null
  title: string | null
  displayTitle: string
  createdAt: number | null
  updatedAt: number | null
  filePath: string
}

export interface BootstrapPayload {
  platform: string
  version: string
  dataDirs: {
    dshHome: string
    profileDirectory: string
    settingsDirectory: string
    pluginSourcesDirectory: string
  }
  settings: AppSettingsData
  environment: {
    state: EnvironmentState
    tools: Toolchain
    isWorking: boolean
  }
  web: WebServerState
  sessions: SessionSummary[]
  plugins: InstalledPlugin[]
  profiles: string[]
  profileName: string
  logs: Record<LogSource, LogEntry[]>
}

export type InstallKind = 'github' | 'zip' | 'folder' | 'npm'

export interface WebBounds {
  x: number
  y: number
  width: number
  height: number
}

export interface WebNavigationState {
  canGoBack: boolean
  canGoForward: boolean
  zoomFactor: number
  loading: boolean
  title: string
}

export interface InstallDraft {
  kind: InstallKind
  githubText?: string
  npmText?: string
  filePath?: string
}
