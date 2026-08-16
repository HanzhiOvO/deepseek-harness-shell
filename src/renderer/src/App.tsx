import { useEffect, useState } from 'react'
import {
  Activity,
  Blocks,
  Command,
  History,
  MessageSquare,
  Monitor,
  Moon,
  ScrollText,
  Search,
  Settings,
  Square,
  Play,
  Sun
} from 'lucide-react'
import { appStore, useAppStore } from './state/store'
import Sidebar from './components/Sidebar'
import ChatView from './views/ChatView'
import HistoryView from './views/HistoryView'
import PluginsView from './views/PluginsView'
import LogsView from './views/LogsView'
import SettingsView from './views/SettingsView'
import CommandPalette from './components/CommandPalette'
import Toasts from './components/Toasts'
import AboutModal from './components/AboutModal'

const VIEW_META = {
  chat: { title: '对话', subtitle: 'DeepSeek Harness 工作区', icon: MessageSquare },
  history: { title: '历史会话', subtitle: '本地会话记录', icon: History },
  plugins: { title: '插件中心', subtitle: '管理 profile 插件', icon: Blocks },
  logs: { title: '运行日志', subtitle: '环境 / 服务 / 插件', icon: ScrollText },
  settings: { title: '环境与设置', subtitle: '工具链与偏好', icon: Settings }
} as const

export default function App(): React.JSX.Element {
  const snapshot = useAppStore()
  const [aboutOpen, setAboutOpen] = useState(false)

  useEffect(() => {
    const applyTheme = (): void => {
      const mode = snapshot.settings?.appearance ?? 'system'
      const dark = mode === 'dark' || (mode === 'system' && window.matchMedia('(prefers-color-scheme: dark)').matches)
      document.documentElement.classList.toggle('dark', dark)
    }
    applyTheme()
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    media.addEventListener('change', applyTheme)
    return () => media.removeEventListener('change', applyTheme)
  }, [snapshot.settings?.appearance])

  useEffect(() => {
    const onKey = (event: KeyboardEvent): void => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault()
        appStore.setPaletteOpen(!snapshot.paletteOpen)
      }
      if (event.key === 'Escape') appStore.setPaletteOpen(false)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [snapshot.paletteOpen])

  if (!snapshot.initialized) {
    return <Splash />
  }

  const meta = VIEW_META[snapshot.view]

  return (
    <div className="flex h-full flex-col bg-ink-50 text-ink-900 dark:bg-ink-950 dark:text-ink-50">
      <Topbar meta={meta} setAboutOpen={setAboutOpen} />
      <div className="flex min-h-0 flex-1">
        <Sidebar />
        <main className="min-w-0 flex-1 overflow-hidden">
          {snapshot.view === 'chat' && <ChatView />}
          {snapshot.view === 'history' && <HistoryView />}
          {snapshot.view === 'plugins' && <PluginsView />}
          {snapshot.view === 'logs' && <LogsView />}
          {snapshot.view === 'settings' && <SettingsView />}
        </main>
      </div>
      {snapshot.paletteOpen && <CommandPalette />}
      <Toasts />
      <AboutModal open={aboutOpen} onClose={() => setAboutOpen(false)} />
    </div>
  )
}

function Topbar({
  meta,
  setAboutOpen
}: {
  meta: { title: string; subtitle: string; icon: typeof MessageSquare }
  setAboutOpen: (open: boolean) => void
}): React.JSX.Element {
  const snapshot = useAppStore()
  const Icon = meta.icon
  const running = snapshot.webState.kind === 'running'
  const starting = snapshot.webState.kind === 'starting'
  const appearance = snapshot.settings?.appearance ?? 'system'

  const cycleAppearance = (): void => {
    const next = appearance === 'system' ? 'light' : appearance === 'light' ? 'dark' : 'system'
    void window.api.settings.update({ appearance: next })
  }

  return (
    <header
      className={`app-drag relative z-20 flex h-12 shrink-0 items-center gap-3 border-b border-ink-200/70 bg-white/75 px-3 glass dark:border-white/[0.06] dark:bg-ink-900/70 ${
        window.api.platform === 'darwin' ? 'pl-[86px]' : 'pl-3'
      }`}
    >
      <div className="flex min-w-0 items-center gap-2.5">
        <span className="grid size-7 place-items-center rounded-lg bg-brand-100 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
          <Icon size={15} strokeWidth={2.2} />
        </span>
        <div className="min-w-0 leading-tight">
          <div className="truncate text-[13px] font-semibold">{meta.title}</div>
          <div className="truncate text-[10.5px] text-ink-500 dark:text-ink-400">{meta.subtitle}</div>
        </div>
      </div>

      <div className="flex-1" />

      <div className="app-no-drag flex items-center gap-2">
        <ServicePill />
        <button
          onClick={cycleAppearance}
          className="grid size-7 place-items-center rounded-lg text-ink-500 transition hover:bg-ink-100 hover:text-ink-900 dark:text-ink-400 dark:hover:bg-white/5 dark:hover:text-ink-50"
          title="切换外观"
        >
          {appearance === 'system' ? <Monitor size={14} /> : appearance === 'light' ? <Sun size={14} /> : <Moon size={14} />}
        </button>
        <button
          onClick={() => appStore.setPaletteOpen(true)}
          className="flex h-7 items-center gap-1.5 rounded-lg border border-ink-200 bg-white px-2 text-[11px] font-medium text-ink-500 shadow-sm transition hover:border-brand-300 hover:text-brand-600 dark:border-white/10 dark:bg-white/5 dark:text-ink-400 dark:hover:text-brand-300"
          title="快速跳转"
        >
          <Search size={12} />
          <span className="hidden xl:inline">搜索</span>
          <span className="flex items-center gap-0.5 font-mono text-[10px]">
            <Command size={10} />K
          </span>
        </button>
        <button
          onClick={() => setAboutOpen(true)}
          className="grid size-7 place-items-center rounded-lg text-ink-500 transition hover:bg-ink-100 hover:text-ink-900 dark:text-ink-400 dark:hover:bg-white/5 dark:hover:text-ink-50"
          title="关于"
        >
          <Activity size={14} />
        </button>
        <button
          onClick={() => (running ? void window.api.web.stop() : void window.api.web.start())}
          disabled={starting}
          className={`flex h-7 items-center gap-1.5 rounded-lg px-2.5 text-[11px] font-semibold text-white shadow-sm transition disabled:cursor-not-allowed disabled:opacity-60 ${
            running
              ? 'bg-red-500/90 hover:bg-red-600'
              : 'bg-gradient-to-br from-brand-400 to-brand-700 hover:brightness-110'
          }`}
        >
          {starting ? (
            <span className="size-3 animate-spin rounded-full border-2 border-white/40 border-t-white" />
          ) : running ? (
            <Square size={11} fill="currentColor" />
          ) : (
            <Play size={11} fill="currentColor" />
          )}
          {running ? '停止' : starting ? '启动中' : '启动'}
        </button>
      </div>
    </header>
  )
}

function ServicePill(): React.JSX.Element {
  const snapshot = useAppStore()
  const state = snapshot.webState
  const config = {
    running: { dot: 'bg-emerald-500', label: 'Harness 运行中', text: 'text-emerald-600 dark:text-emerald-400' },
    starting: { dot: 'bg-amber-500 animate-soft-pulse', label: '正在启动…', text: 'text-amber-600 dark:text-amber-400' },
    failed: { dot: 'bg-red-500', label: '服务异常', text: 'text-red-600 dark:text-red-400' },
    stopped: { dot: 'bg-ink-300 dark:bg-ink-600', label: '未启动', text: 'text-ink-500 dark:text-ink-400' }
  }[state.kind]
  const url = state.kind === 'running' ? state.url.replace(/^https?:\/\//, '') : ''

  return (
    <div
      className="flex h-7 items-center gap-2 rounded-full border border-ink-200 bg-white/80 px-2.5 dark:border-white/10 dark:bg-white/[0.04]"
      title={state.kind === 'failed' ? state.error : url}
    >
      <span className={`size-1.5 rounded-full ${config.dot}`} />
      <span className={`text-[11px] font-medium ${config.text}`}>{config.label}</span>
      {url && <span className="hidden font-mono text-[10px] text-ink-400 lg:inline">{url}</span>}
    </div>
  )
}

function Splash(): React.JSX.Element {
  return (
    <div className="grid h-full place-items-center bg-ink-950 text-white">
      <div className="flex flex-col items-center gap-5">
        <div className="grid size-16 place-items-center rounded-[20px] bg-gradient-to-br from-brand-400 to-brand-900 shadow-lifted">
          <Command size={28} />
        </div>
        <div className="shimmer h-2 w-40 rounded-full" />
        <div className="text-xs tracking-wide text-ink-400">DeepSeek Harness Shell · 正在启动</div>
      </div>
    </div>
  )
}
