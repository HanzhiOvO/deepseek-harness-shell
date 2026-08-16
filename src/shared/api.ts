import type {
  AppSettingsData,
  BootstrapPayload,
  EnvironmentState,
  InstallDraft,
  InstalledPlugin,
  LogEntry,
  SessionSummary,
  Toolchain,
  WebBounds,
  WebNavigationState,
  WebServerState
} from './types'

export type EventChannel =
  | 'log'
  | 'env-state'
  | 'tools'
  | 'web-state'
  | 'web-navigation'
  | 'web-session-result'
  | 'sessions'
  | 'plugins'
  | 'profiles'
  | 'settings'
  | 'menu-action'
  | 'open-session'

export interface DesktopApi {
  platform: string
  bootstrap(): Promise<BootstrapPayload>

  environment: {
    detect(): Promise<EnvironmentState>
    installDsh(): Promise<boolean>
    updateDsh(): Promise<boolean>
    installNode(): Promise<boolean>
    ensurePnpm(): Promise<boolean>
  }

  web: {
    start(): Promise<WebServerState>
    stop(): Promise<WebServerState>
    reload(): Promise<void>
    back(): Promise<void>
    forward(): Promise<void>
    zoomIn(): Promise<void>
    zoomOut(): Promise<void>
    zoomReset(): Promise<void>
    openExternal(): Promise<void>
    openWindow(): Promise<void>
    setBounds(bounds: WebBounds): Promise<void>
    openSession(id: string, title: string): Promise<void>
  }

  sessions: {
    sync(): Promise<void>
    togglePin(id: string): Promise<boolean>
    reveal(filePath: string): Promise<void>
  }

  plugins: {
    refresh(): Promise<void>
    setProfile(name: string): Promise<void>
    install(draft: InstallDraft): Promise<void>
    update(name: string): Promise<void>
    remove(name: string): Promise<void>
    pickZip(): Promise<string | null>
    pickFolder(): Promise<string | null>
  }

  settings: {
    update(patch: Partial<AppSettingsData>): Promise<AppSettingsData>
    reset(): Promise<AppSettingsData>
  }

  logs: {
    clear(source?: LogEntry['source']): Promise<void>
    export(text: string, defaultName: string): Promise<boolean>
  }

  shell: {
    openExternal(url: string): Promise<void>
    reveal(path: string): Promise<void>
    openPath(path: string): Promise<void>
    pathForFile(file: unknown): string
  }

  on(channel: 'log', listener: (entry: LogEntry) => void): () => void
  on(channel: 'env-state', listener: (state: EnvironmentState) => void): () => void
  on(channel: 'tools', listener: (tools: Toolchain) => void): () => void
  on(channel: 'web-state', listener: (state: WebServerState) => void): () => void
  on(channel: 'web-navigation', listener: (state: WebNavigationState) => void): () => void
  on(channel: 'web-session-result', listener: (payload: { sessionId: string; opened: boolean }) => void): () => void
  on(channel: 'sessions', listener: (sessions: SessionSummary[]) => void): () => void
  on(channel: 'plugins', listener: (plugins: InstalledPlugin[]) => void): () => void
  on(channel: 'profiles', listener: (profiles: string[]) => void): () => void
  on(channel: 'settings', listener: (settings: AppSettingsData) => void): () => void
  on(channel: 'menu-action', listener: (action: string) => void): () => void
  on(channel: 'open-session', listener: (session: SessionSummary) => void): () => void
}
