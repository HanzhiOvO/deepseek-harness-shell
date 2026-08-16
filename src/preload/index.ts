import { contextBridge, ipcRenderer, webUtils } from 'electron'
import type { DesktopApi } from '@shared/api'

function subscribe(channel: string, listener: (payload: unknown) => void): () => void {
  const wrapped = (_event: Electron.IpcRendererEvent, payload: unknown): void => listener(payload)
  ipcRenderer.on(channel, wrapped)
  return () => ipcRenderer.removeListener(channel, wrapped)
}

const api: DesktopApi = {
  platform: process.platform,
  bootstrap: () => ipcRenderer.invoke('app:bootstrap'),

  environment: {
    detect: () => ipcRenderer.invoke('env:detect'),
    installDsh: () => ipcRenderer.invoke('env:install-dsh'),
    updateDsh: () => ipcRenderer.invoke('env:update-dsh'),
    installNode: () => ipcRenderer.invoke('env:install-node'),
    ensurePnpm: () => ipcRenderer.invoke('env:ensure-pnpm')
  },

  web: {
    start: () => ipcRenderer.invoke('web:start'),
    stop: () => ipcRenderer.invoke('web:stop'),
    reload: () => ipcRenderer.invoke('web:reload'),
    back: () => ipcRenderer.invoke('web:back'),
    forward: () => ipcRenderer.invoke('web:forward'),
    zoomIn: () => ipcRenderer.invoke('web:zoom-in'),
    zoomOut: () => ipcRenderer.invoke('web:zoom-out'),
    zoomReset: () => ipcRenderer.invoke('web:zoom-reset'),
    openExternal: () => ipcRenderer.invoke('web:open-external'),
    setBounds: (bounds) => ipcRenderer.invoke('web:set-bounds', bounds),
    openSession: (id, title) => ipcRenderer.invoke('web:open-session', { id, title, displayTitle: title })
  },

  sessions: {
    sync: () => ipcRenderer.invoke('sessions:sync'),
    togglePin: (id) => ipcRenderer.invoke('sessions:toggle-pin', id),
    reveal: (filePath) => ipcRenderer.invoke('sessions:reveal', filePath)
  },

  plugins: {
    refresh: () => ipcRenderer.invoke('plugins:refresh'),
    setProfile: (name) => ipcRenderer.invoke('plugins:set-profile', name),
    install: (draft) => ipcRenderer.invoke('plugins:install', draft),
    update: (name) => ipcRenderer.invoke('plugins:update', name),
    remove: (name) => ipcRenderer.invoke('plugins:remove', name),
    pickZip: () => ipcRenderer.invoke('plugins:pick-zip'),
    pickFolder: () => ipcRenderer.invoke('plugins:pick-folder')
  },

  settings: {
    update: (patch) => ipcRenderer.invoke('settings:update', patch),
    reset: () => ipcRenderer.invoke('settings:reset')
  },

  logs: {
    clear: (source) => ipcRenderer.invoke('logs:clear', source),
    export: (text, defaultName) => ipcRenderer.invoke('logs:export', text, defaultName)
  },

  shell: {
    openExternal: (url) => ipcRenderer.invoke('shell:open-external', url),
    reveal: (path) => ipcRenderer.invoke('shell:reveal', path),
    openPath: (path) => ipcRenderer.invoke('shell:open-path', path),
    pathForFile: (file) => webUtils.getPathForFile(file as File)
  },

  on: ((channel: string, listener: (payload: unknown) => void) => subscribe(`event:${channel}`, listener)) as DesktopApi['on']
}

contextBridge.exposeInMainWorld('api', api)
