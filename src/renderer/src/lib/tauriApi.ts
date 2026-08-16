import { invoke } from '@tauri-apps/api/core'
import { listen } from '@tauri-apps/api/event'
import { getCurrentWebview } from '@tauri-apps/api/webview'
import type { DesktopApi } from '@shared/api'

type Handler = (payload: unknown) => void

function on(channel: string, listener: Handler): () => void {
  void listen(`event:${channel}`, (event) => listener(event.payload))
  return () => undefined
}

let droppedPath = ''
void getCurrentWebview().onDragDropEvent((event) => {
  if (event.payload.type === 'drop' && event.payload.paths.length > 0) {
    droppedPath = event.payload.paths[0]
  }
})

const noop = async (): Promise<void> => undefined

const api: DesktopApi = {
  platform: /Windows/i.test(navigator.userAgent) ? 'win32' : /Mac/i.test(navigator.userAgent) ? 'darwin' : 'linux',
  bootstrap: () => invoke('app_bootstrap'),

  environment: {
    detect: () => invoke('env_detect'),
    installDsh: () => invoke('env_install_dsh'),
    updateDsh: () => invoke('env_update_dsh'),
    installNode: () => invoke('env_install_node'),
    ensurePnpm: () => invoke('env_ensure_pnpm')
  },

  web: {
    start: () => invoke('web_start'),
    stop: () => invoke('web_stop'),
    reload: noop,
    back: noop,
    forward: noop,
    zoomIn: noop,
    zoomOut: noop,
    zoomReset: noop,
    openExternal: () => invoke('web_open_external'),
    openWindow: () => invoke('web_open_window'),
    setBounds: noop,
    openSession: (id, title) => invoke('web_open_session', { request: { id, displayTitle: title } })
  },

  sessions: {
    sync: () => invoke('sessions_sync'),
    togglePin: (id) => invoke('sessions_toggle_pin', { id }),
    reveal: (filePath) => invoke('sessions_reveal', { path: filePath })
  },

  plugins: {
    refresh: () => invoke('plugins_refresh'),
    setProfile: (name) => invoke('plugins_set_profile', { name }),
    install: (draft) => invoke('plugins_install', { draft }),
    update: (name) => invoke('plugins_update', { name }),
    remove: (name) => invoke('plugins_remove', { name }),
    pickZip: () => invoke('plugins_pick_zip'),
    pickFolder: () => invoke('plugins_pick_folder')
  },

  settings: {
    update: (patch) => invoke('settings_update', { patch }),
    reset: () => invoke('settings_reset')
  },

  logs: {
    clear: (source) => invoke('logs_clear', { source }),
    export: (text, defaultName) => invoke('logs_export', { text, defaultName })
  },

  shell: {
    openExternal: (url) => invoke('shell_open_external', { url }),
    reveal: (path) => invoke('shell_reveal', { path }),
    openPath: (path) => invoke('shell_open_path', { path }),
    pathForFile: () => droppedPath
  },

  on: ((channel: string, listener: Handler) => on(channel, listener)) as DesktopApi['on']
}

declare global {
  interface Window {
    api: DesktopApi
  }
}

window.api = api
