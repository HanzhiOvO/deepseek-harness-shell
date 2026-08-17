import { useSyncExternalStore } from 'react'
import type {
  AppSettingsData,
  EnvironmentState,
  InstalledPlugin,
  LogEntry,
  LogSource,
  SessionSummary,
  Toolchain,
  ViewId,
  WebNavigationState,
  WebServerState
} from '@shared/types'

export type ToastKind = 'info' | 'success' | 'error'
export interface Toast {
  id: number
  kind: ToastKind
  message: string
}

export interface AppSnapshot {
  initialized: boolean
  initializationError: string | null
  appVersion: string
  view: ViewId
  paletteOpen: boolean
  dataDirs: {
    dshHome: string
    profileDirectory: string
    settingsDirectory: string
    pluginSourcesDirectory: string
  }
  settings: AppSettingsData | null
  envState: EnvironmentState | null
  tools: Toolchain
  envWorking: boolean
  webState: WebServerState
  webNavigation: WebNavigationState
  sessions: SessionSummary[]
  plugins: InstalledPlugin[]
  profiles: string[]
  logs: Record<LogSource, LogEntry[]>
  toasts: Toast[]
}

const EMPTY_TOOLS: Toolchain = {
  dsh: null,
  node: null,
  npm: null,
  pnpm: null,
  git: null,
  brew: null,
  knownBinDirectories: []
}

let snapshot: AppSnapshot = {
  initialized: false,
  initializationError: null,
  appVersion: '1.2.0',
  view: 'chat',
  paletteOpen: false,
  dataDirs: { dshHome: '', profileDirectory: '', settingsDirectory: '', pluginSourcesDirectory: '' },
  settings: null,
  envState: null,
  tools: EMPTY_TOOLS,
  envWorking: false,
  webState: { kind: 'stopped' },
  webNavigation: { canGoBack: false, canGoForward: false, zoomFactor: 1, loading: false, title: 'DeepSeek Harness' },
  sessions: [],
  plugins: [],
  profiles: ['web'],
  logs: { environment: [], web: [], plugins: [], sessions: [] },
  toasts: []
}

let toastId = 1
const listeners = new Set<() => void>()

function emit(): void {
  snapshot = { ...snapshot }
  for (const listener of listeners) listener()
}

function patch(partial: Partial<AppSnapshot>): void {
  Object.assign(snapshot, partial)
  emit()
}

function appendLog(entry: LogEntry): void {
  const list = [...snapshot.logs[entry.source]]
  list.push(entry)
  if (list.length > 900) list.splice(0, list.length - 900)
  const logs = { ...snapshot.logs, [entry.source]: list }
  patch({ logs })
}

export const appStore = {
  subscribe(listener: () => void): () => void {
    listeners.add(listener)
    return () => listeners.delete(listener)
  },
  getSnapshot(): AppSnapshot {
    return snapshot
  },
  setView(view: ViewId): void {
    patch({ view })
  },
  setPaletteOpen(open: boolean): void {
    patch({ paletteOpen: open })
  },
  toast(message: string, kind: ToastKind = 'info'): void {
    const id = toastId++
    const toasts = [...snapshot.toasts, { id, kind, message }]
    patch({ toasts })
    window.setTimeout(() => {
      patch({ toasts: snapshot.toasts.filter((toast) => toast.id !== id) })
    }, 4200)
  },
  appendLog,
  async initialize(): Promise<void> {
    patch({ initializationError: null })
    try {
      const payload = await window.api.bootstrap()
      patch({
        initialized: true,
        initializationError: null,
        appVersion: payload.version,
        dataDirs: payload.dataDirs,
        settings: payload.settings,
        envState: payload.environment.state,
        tools: payload.environment.tools,
        envWorking: payload.environment.isWorking,
        webState: payload.web,
        sessions: payload.sessions,
        plugins: payload.plugins,
        profiles: payload.profiles,
        logs: payload.logs
      })
    } catch (error) {
      patch({ initializationError: error instanceof Error ? error.message : String(error) })
    }
  }
}

if (typeof window !== 'undefined' && window.api) {
  window.api.on('log', (entry) => appStore.appendLog(entry))
  window.api.on('env-state', (state) => patch({ envState: state, envWorking: state.kind === 'checking' || state.kind === 'installing' }))
  window.api.on('tools', (tools) => patch({ tools }))
  window.api.on('web-state', (state) => patch({ webState: state }))
  window.api.on('web-navigation', (state) => patch({ webNavigation: state }))
  window.api.on('sessions', (sessions) => patch({ sessions }))
  window.api.on('plugins', (plugins) => patch({ plugins }))
  window.api.on('profiles', (profiles) => patch({ profiles }))
  window.api.on('settings', (settings) => patch({ settings }))
  window.api.on('logs', (logs) => patch({ logs }))
  window.api.on('menu-action', (action) => {
    if (action === 'palette') appStore.setPaletteOpen(true)
    else if (action === 'plugins') appStore.setView('plugins')
    else if (action === 'history') appStore.setView('history')
  })
  window.api.on('open-session', (session) => {
    appStore.setView('chat')
    void window.api.web.openSession(session.id, session.displayTitle)
  })
  window.api.on('web-session-result', (payload) => {
    appStore.toast(payload.opened ? '会话已在 Harness 中打开' : '未能自动定位该会话，可在 Web UI 内手动选择', payload.opened ? 'success' : 'error')
  })
}

export function useAppStore(): AppSnapshot {
  return useSyncExternalStore(appStore.subscribe, appStore.getSnapshot)
}
