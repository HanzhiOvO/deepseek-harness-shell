import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  nativeImage,
  shell,
  Tray,
  type MenuItemConstructorOptions
} from 'electron'
import { existsSync } from 'node:fs'
import { promises as fs } from 'node:fs'
import { join } from 'node:path'
import { LogBus } from './core/logBus'
import { SettingsService } from './services/settingsService'
import { EnvironmentService } from './services/environmentService'
import { WebServerService } from './services/webServerService'
import { PluginService } from './services/pluginService'
import { SessionService } from './services/sessionService'
import { EmbeddedHarness } from './services/embeddedHarness'
import type {
  AppSettingsData,
  BootstrapPayload,
  InstallDraft,
  InstalledPlugin,
  LogEntry,
  LogSource,
  SessionSummary,
  WebBounds,
  WebServerState
} from '@shared/types'

const portableUserData = process.env.DSH_SHELL_USER_DATA?.trim()
if (portableUserData) {
  app.setPath('userData', portableUserData)
}

let mainWindow: BrowserWindow | null = null
let tray: Tray | null = null
let isQuitting = false
let bootstrapDone = false

const logBus = new LogBus()
const send = (channel: string, payload?: unknown): void => {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send(channel, payload)
  }
}

let settingsService!: SettingsService
let environmentService!: EnvironmentService
let webService!: WebServerService
let pluginService!: PluginService
let sessionService!: SessionService
let embedded!: EmbeddedHarness

function initializeServices(): void {
  settingsService = new SettingsService((settings) => send('event:settings', settings))

  environmentService = new EnvironmentService(
    settingsService,
    logBus,
    (state) => send('event:env-state', state),
    (tools) => send('event:tools', tools)
  )

  webService = new WebServerService(environmentService, settingsService, logBus, (state) => {
    send('event:web-state', state)
    onWebStateChanged(state)
    rebuildTray()
  })

  pluginService = new PluginService(
    settingsService,
    environmentService,
    logBus,
    (plugins) => send('event:plugins', plugins),
    (profiles) => send('event:profiles', profiles)
  )

  sessionService = new SessionService(
    settingsService,
    environmentService,
    logBus,
    (sessions) => {
      send('event:sessions', sessions)
      rebuildTray()
    }
  )

  embedded = new EmbeddedHarness(
    (state) => send('event:web-navigation', state),
    (sessionId, opened) => send('event:web-session-result', { sessionId, opened })
  )
}

function onWebStateChanged(state: WebServerState): void {
  if (state.kind === 'running' && mainWindow) {
    if (!embedded.isAttached) {
      const [width, height] = mainWindow.getContentSize()
      const defaultBounds = { x: 260, y: 48, width: Math.max(width - 260, 200), height: Math.max(height - 48, 200) }
      embedded.attach(mainWindow, defaultBounds)
    }
    void embedded.load(state.url)
  } else if (state.kind !== 'running' && state.kind !== 'starting') {
    embedded.destroy()
  }
}

function createMainWindow(): void {
  mainWindow = new BrowserWindow({
    title: 'DeepSeek Harness Shell',
    width: 1220,
    height: 800,
    minWidth: 980,
    minHeight: 660,
    show: false,
    backgroundColor: '#0b0f1a',
    titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
    trafficLightPosition: process.platform === 'darwin' ? { x: 18, y: 17 } : undefined,
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false
    }
  })

  mainWindow.once('ready-to-show', () => {
    mainWindow?.show()
  })

  mainWindow.on('close', (event) => {
    if (!isQuitting && !settingsService.get().stopWhenClosed) {
      event.preventDefault()
      mainWindow?.hide()
    }
  })

  mainWindow.on('closed', () => {
    mainWindow = null
  })

  if (process.env.ELECTRON_RENDERER_URL) {
    void mainWindow.loadURL(process.env.ELECTRON_RENDERER_URL)
  } else {
    void mainWindow.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

function installMenu(): void {
  const isMac = process.platform === 'darwin'
  const template: MenuItemConstructorOptions[] = [
    ...(isMac
      ? [
          {
            label: app.name,
            submenu: [
              { role: 'about' as const },
              { type: 'separator' as const },
              { role: 'services' as const },
              { type: 'separator' as const },
              { role: 'hide' as const },
              { role: 'hideOthers' as const },
              { role: 'unhide' as const },
              { type: 'separator' as const },
              { role: 'quit' as const }
            ]
          }
        ]
      : []),
    {
      label: '服务',
      submenu: [
        {
          label: '启动服务',
          accelerator: 'CmdOrCtrl+R',
          click: () => webService.start()
        },
        {
          label: '停止服务',
          accelerator: 'CmdOrCtrl+.',
          click: () => webService.stop()
        },
        { type: 'separator' },
        {
          label: '插件中心',
          accelerator: 'CmdOrCtrl+Shift+P',
          click: () => send('event:menu-action', 'plugins')
        },
        {
          label: '快速跳转…',
          accelerator: 'CmdOrCtrl+K',
          click: () => send('event:menu-action', 'palette')
        },
        {
          label: '历史会话',
          accelerator: 'CmdOrCtrl+Shift+H',
          click: () => send('event:menu-action', 'history')
        }
      ]
    },
    ...(isMac ? [{ role: 'editMenu' as const }] : []),
    {
      label: '显示',
      submenu: [
        {
          label: '放大',
          accelerator: 'CmdOrCtrl+Plus',
          click: () => embedded.zoomIn()
        },
        {
          label: '缩小',
          accelerator: 'CmdOrCtrl+-',
          click: () => embedded.zoomOut()
        },
        {
          label: '实际大小',
          accelerator: 'CmdOrCtrl+0',
          click: () => embedded.zoomReset()
        },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { role: 'toggleDevTools' }
      ]
    },
    {
      label: '窗口',
      submenu: [{ role: 'minimize' }, { role: 'zoom' }, ...(isMac ? [{ role: 'front' as const }] : [{ role: 'close' as const }])]
    },
    {
      role: 'help',
      submenu: [
        {
          label: 'DeepSeek Harness 官方仓库',
          click: () => void shell.openExternal('https://github.com/deepseek-ai/deepseek-harness')
        },
        {
          label: 'Node.js 下载',
          click: () => void shell.openExternal('https://nodejs.org/zh-cn/download')
        }
      ]
    }
  ]
  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}

function trayIcon(): Electron.NativeImage | undefined {
  const candidates = [
    join(app.getAppPath(), 'resources', 'icon.png'),
    join(__dirname, '../../resources/icon.png')
  ]
  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      const image = nativeImage.createFromPath(candidate)
      if (!image.isEmpty()) return image.resize({ width: 18, height: 18 })
    }
  }
  return undefined
}

function createTray(): void {
  if (tray) return
  const icon = trayIcon()
  tray = new Tray(icon ?? nativeImage.createEmpty())
  tray.setToolTip('DeepSeek Harness Shell')
  tray.on('click', () => {
    if (process.platform !== 'darwin') showMainWindow()
  })
  rebuildTray()
}

function rebuildTray(): void {
  if (!tray) return
  const running = webService.state.kind === 'running'
  const recent = sessionService.sessions.slice(0, 5)
  const menu = Menu.buildFromTemplate([
    {
      label: 'DeepSeek Harness Shell',
      enabled: false
    },
    {
      label: webService.state.kind === 'running' ? '状态：运行中' : webService.state.kind === 'starting' ? '状态：正在启动…' : '状态：未启动',
      enabled: false
    },
    { type: 'separator' },
    {
      label: running ? '停止服务' : '启动服务',
      click: () => (running ? webService.stop() : webService.start())
    },
    {
      label: '显示主窗口',
      click: () => showMainWindow()
    },
    { type: 'separator' },
    ...(recent.length > 0
      ? [
          ...recent.map(
            (session) =>
              ({
                label: session.displayTitle.slice(0, 48),
                click: () => openSessionInHarness(session)
              }) satisfies MenuItemConstructorOptions
          ),
          { type: 'separator' as const }
        ]
      : []),
    {
      label: '插件中心',
      click: () => {
        showMainWindow()
        send('event:menu-action', 'plugins')
      }
    },
    {
      label: '退出 DeepSeek Harness Shell',
      click: () => {
        isQuitting = true
        app.quit()
      }
    }
  ])
  tray.setContextMenu(menu)
}

function showMainWindow(): void {
  if (!mainWindow) {
    createMainWindow()
  }
  mainWindow?.show()
  mainWindow?.focus()
  app.dock?.show().catch(() => undefined)
}

function openSessionInHarness(session: SessionSummary): void {
  showMainWindow()
  send('event:open-session', session)
}

async function runBootstrap(): Promise<void> {
  if (bootstrapDone) return
  bootstrapDone = true
  await settingsService.load()
  await environmentService.detect()
  await pluginService.refreshProfiles()

  const env = environmentService.state
  const settings = settingsService.get()
  if (env.kind === 'missing-dsh' && settings.autoInstallDsh && env.canInstall) {
    if (await environmentService.installDsh()) {
      await pluginService.refreshProfiles()
    }
  }
  if (environmentService.state.kind === 'ready' && settings.autoStartWeb) {
    webService.start()
  }
  await sessionService.sync(true)
}

function bootstrapPayload(): BootstrapPayload {
  return {
    platform: process.platform,
    version: app.getVersion(),
    dataDirs: {
      dshHome: pluginService.dshHomeDirectory,
      profileDirectory: pluginService.profileDirectory,
      settingsDirectory: app.getPath('userData'),
      pluginSourcesDirectory: join(app.getPath('userData'), 'PluginSources')
    },
    settings: settingsService.get(),
    environment: {
      state: environmentService.state,
      tools: environmentService.tools,
      isWorking: environmentService.isWorking
    },
    web: webService.state,
    sessions: sessionService.sessions,
    plugins: pluginService.installed,
    profiles: pluginService.profiles,
    profileName: pluginService.profileName,
    logs: logBus.snapshot()
  }
}

// MARK: - IPC

function registerIpc(): void {
  ipcMain.handle('app:bootstrap', () => bootstrapPayload())
  ipcMain.handle('env:detect', () => environmentService.detect().then(() => environmentService.state))
  ipcMain.handle('env:install-dsh', () => environmentService.installDsh())
  ipcMain.handle('env:update-dsh', () => environmentService.updateDsh())
  ipcMain.handle('env:install-node', () => environmentService.installNode())
  ipcMain.handle('env:ensure-pnpm', () => environmentService.ensurePnpm())

  ipcMain.handle('web:start', () => {
    webService.start()
    return webService.state
  })
  ipcMain.handle('web:stop', () => {
    webService.stop()
    return webService.state
  })
  ipcMain.handle('web:reload', () => embedded.reload())
  ipcMain.handle('web:back', () => embedded.goBack())
  ipcMain.handle('web:forward', () => embedded.goForward())
  ipcMain.handle('web:zoom-in', () => embedded.zoomIn())
  ipcMain.handle('web:zoom-out', () => embedded.zoomOut())
  ipcMain.handle('web:zoom-reset', () => embedded.zoomReset())
  ipcMain.handle('web:open-external', () => {
    if (webService.state.kind === 'running') return shell.openExternal(webService.state.url)
    return undefined
  })
  ipcMain.handle('web:set-bounds', (_event, bounds: WebBounds) => {
    if (
      bounds &&
      [bounds.x, bounds.y, bounds.width, bounds.height].every((value) => Number.isFinite(value) && value >= 0)
    ) {
      embedded.setBounds(bounds)
    }
  })
  ipcMain.handle('web:open-session', (_event, session: SessionSummary) => {
    if (webService.state.kind !== 'running') {
      embedded.openSession(session.id, session.displayTitle)
      webService.start()
    } else {
      embedded.openSession(session.id, session.displayTitle)
    }
  })

  ipcMain.handle('sessions:sync', () => sessionService.sync(true))
  ipcMain.handle('sessions:toggle-pin', (_event, id: string) => settingsService.togglePin(String(id)))
  ipcMain.handle('sessions:reveal', (_event, filePath: string) => shell.showItemInFolder(filePath))

  ipcMain.handle('plugins:refresh', () => pluginService.refreshProfiles())
  ipcMain.handle('plugins:set-profile', (_event, name: string) => pluginService.setProfile(name))
  ipcMain.handle('plugins:install', (_event, draft: InstallDraft) => installPluginDraft(draft))
  ipcMain.handle('plugins:update', async (_event, name: string) => {
    const plugin = pluginService.installed.find((item) => item.name === name)
    if (!plugin) throw new Error('未找到该插件')
    await pluginService.update(plugin)
  })
  ipcMain.handle('plugins:remove', async (_event, name: string) => {
    const plugin = pluginService.installed.find((item) => item.name === name)
    if (!plugin) throw new Error('未找到该插件')
    await pluginService.remove(plugin)
  })
  ipcMain.handle('plugins:pick-zip', async () => {
    const result = await dialog.showOpenDialog(mainWindow!, {
      title: '选择插件 ZIP 压缩包',
      properties: ['openFile'],
      filters: [{ name: 'ZIP 压缩包', extensions: ['zip'] }]
    })
    return result.canceled ? null : (result.filePaths[0] ?? null)
  })
  ipcMain.handle('plugins:pick-folder', async () => {
    const result = await dialog.showOpenDialog(mainWindow!, {
      title: '选择插件文件夹',
      properties: ['openDirectory']
    })
    return result.canceled ? null : (result.filePaths[0] ?? null)
  })

  ipcMain.handle('settings:update', (_event, patch: Partial<AppSettingsData>) => {
    const updated = settingsService.update(patch)
    environmentService.refreshOverrides()
    if (patch.dshHome !== undefined) void sessionService.sync(true)
    if (patch.profileName !== undefined) pluginService.setProfile(patch.profileName)
    return updated
  })
  ipcMain.handle('settings:reset', () => settingsService.reset())

  ipcMain.handle('logs:clear', (_event, source?: LogSource) => logBus.clear(source))
  ipcMain.handle('logs:export', async (_event, text: string, defaultName: string) => {
    const result = await dialog.showSaveDialog(mainWindow!, {
      title: '导出运行日志',
      defaultPath: defaultName,
      filters: [{ name: '文本文件', extensions: ['txt'] }]
    })
    if (result.canceled || !result.filePath) return false
    await fs.writeFile(result.filePath, text, 'utf8')
    return true
  })

  ipcMain.handle('shell:open-external', (_event, url: string) => {
    if (/^https?:\/\//.test(url)) return shell.openExternal(url)
    return undefined
  })
  ipcMain.handle('shell:reveal', (_event, path: string) => shell.showItemInFolder(path))
  ipcMain.handle('shell:open-path', (_event, path: string) => shell.openPath(path))
}

async function installPluginDraft(draft: InstallDraft): Promise<void> {
  switch (draft.kind) {
    case 'github':
      if (!draft.githubText) throw new Error('请输入 GitHub 仓库地址')
      await pluginService.installFromGitHub(draft.githubText)
      break
    case 'npm':
      if (!draft.npmText) throw new Error('请输入 npm 包名')
      await pluginService.installFromNpm(draft.npmText)
      break
    case 'zip':
      if (!draft.filePath) throw new Error('请选择 .zip 压缩包')
      await pluginService.installFromZip(draft.filePath)
      break
    case 'folder':
      if (!draft.filePath) throw new Error('请选择插件文件夹')
      await pluginService.installFromFolder(draft.filePath)
      break
  }
}

// MARK: - 生命周期

const gotLock = app.requestSingleInstanceLock()
if (!gotLock) {
  app.quit()
} else {
  app.on('second-instance', () => showMainWindow())

  app.whenReady().then(async () => {
    app.setName('DeepSeek Harness Shell')
    initializeServices()
    registerIpc()
    logBus.on((entry) => send('event:log', entry))

    if (process.env.DSH_SHELL_SMOKE === '1') {
      await runSmoke()
      return
    }

    createMainWindow()
    installMenu()
    createTray()
    await runBootstrap()

    if (process.env.DSH_SHELL_GUI_SMOKE === '1' && mainWindow) {
      await new Promise<void>((resolve) => {
        if (!mainWindow) return resolve()
        if (!mainWindow.webContents.isLoading()) resolve()
        else mainWindow.webContents.once('did-finish-load', () => resolve())
      })
      await new Promise((resolve) => setTimeout(resolve, 3500))
      const body = (await mainWindow.webContents.executeJavaScript('document.body.innerText')) as string
      console.log(`GUI ${body.slice(0, 260).replace(/\s+/g, ' ')}`)
      console.log(body.includes('DeepSeek Harness') ? 'GUI PASS' : 'GUI FAIL')
      app.exit(body.includes('DeepSeek Harness') ? 0 : 1)
      return
    }
  })

  app.on('activate', () => {
    if (!mainWindow) createMainWindow()
    mainWindow?.show()
  })

  app.on('before-quit', () => {
    isQuitting = true
    webService.shutdown()
  })

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin' || settingsService.get().stopWhenClosed) {
      app.quit()
    }
  })
}

// 供类型检查使用，避免未使用告警。
export type { LogEntry, InstalledPlugin }


// MARK: - 自动化冒烟模式（DSH_SHELL_SMOKE=1）
async function runSmoke(): Promise<void> {
  try {
    await runBootstrap()
    console.log(`ENV ${environmentService.state.kind} dsh=${environmentService.tools.dsh?.version ?? 'none'}`)
    console.log(`PLUGINS ${pluginService.installed.length} inbox=${pluginService.installed.filter((item) => item.isInbox).length}`)
    console.log(`SESSIONS ${sessionService.sessions.length}`)

    webService.start()
    let url = ''
    for (let index = 0; index < 60; index += 1) {
      if (webService.state.kind === 'running') {
        url = webService.state.url
        break
      }
      if (webService.state.kind === 'failed') throw new Error(`WEB_FAILED ${webService.state.error}`)
      await new Promise((resolve) => setTimeout(resolve, 500))
    }
    if (!url) throw new Error('WEB_TIMEOUT')

    const response = await fetch(url)
    const body = await response.text()
    console.log(`WEB ${response.status} bytes=${body.length} url=${url}`)
    if (response.status !== 200) throw new Error(`WEB_HTTP_${response.status}`)

    webService.stop()

    if (process.env.DSH_SHELL_PLUGIN_SMOKE === '1') {
      const { mkdtemp, writeFile, mkdir } = await import('node:fs/promises')
      const { join } = await import('node:path')
      const { tmpdir } = await import('node:os')
      const folder = await mkdtemp(join(tmpdir(), 'dsh-shell-plugin-smoke-'))
      await writeFile(
        join(folder, 'package.json'),
        JSON.stringify({ name: 'smoke-electron-plugin', version: '0.0.1', private: true, dsh: { bundle: { patch: 'patch.yml' } } }, null, 2),
        'utf8'
      )
      await writeFile(join(folder, 'patch.yml'), '[]\n', 'utf8')
      await mkdir(join(folder, 'src')).catch(() => undefined)

      await pluginService.installFromFolder(folder)
      const installed = pluginService.installed.find((item) => item.name === 'smoke-electron-plugin')
      if (!installed) throw new Error('PLUGIN_NOT_INSTALLED')
      await pluginService.update(installed)
      await pluginService.remove(installed)
      if (pluginService.installed.some((item) => item.name === 'smoke-electron-plugin')) throw new Error('PLUGIN_NOT_REMOVED')
      console.log('PLUGIN SMOKE PASS')
    }

    console.log('SMOKE PASS')
    app.exit(0)
  } catch (error) {
    console.error(`SMOKE FAIL ${String(error)}`)
    app.exit(1)
  }
}
