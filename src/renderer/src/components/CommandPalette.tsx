import { useMemo, useRef, useState } from 'react'
import {
  Blocks,
  History,
  MessageSquare,
  Play,
  RefreshCw,
  ScrollText,
  Search,
  Settings,
  Square
} from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import { relativeTime } from '@shared/parsers'
import type { SessionSummary } from '@shared/types'

type Entry =
  | { kind: 'action'; id: string; title: string; subtitle: string; icon: 'play' | 'stop' | 'sync' | 'view'; view?: string; action: () => void }
  | { kind: 'session'; session: SessionSummary }

export default function CommandPalette(): React.JSX.Element {
  const snapshot = useAppStore()
  const [query, setQuery] = useState('')
  const inputRef = useRef<HTMLInputElement>(null)

  const entries = useMemo<Entry[]>(() => {
    const keyword = query.trim().toLowerCase()
    const result: Entry[] = []
    const running = snapshot.webState.kind === 'running'

    const matches = (...values: string[]): boolean => keyword === '' || values.some((value) => value.toLowerCase().includes(keyword))

    if (matches('启动', '停止', '服务', 'harness', 'web')) {
      result.push({
        kind: 'action',
        id: 'service',
        title: running ? '停止 DeepSeek Harness 服务' : '启动 DeepSeek Harness',
        subtitle: running ? '关闭本机 Web UI 进程并释放内存' : '启动 dsh web 并嵌入官方界面',
        icon: running ? 'stop' : 'play',
        action: () => void (running ? window.api.web.stop() : window.api.web.start())
      })
    }
    if (matches('同步', '刷新', '会话')) {
      result.push({
        kind: 'action',
        id: 'sync',
        title: '同步本地历史会话',
        subtitle: '扫描 DSH_HOME/sessions 并刷新列表',
        icon: 'sync',
        action: () => void window.api.sessions.sync()
      })
    }
    const views = [
      { id: 'chat', label: '对话工作区', subtitle: '内嵌官方 Harness Web UI', icon: 'view' as const, view: 'chat' },
      { id: 'history', label: '历史会话', subtitle: '浏览本地会话记录', icon: 'view' as const, view: 'history' },
      { id: 'plugins', label: '插件中心', subtitle: '管理 profile 插件', icon: 'view' as const, view: 'plugins' },
      { id: 'logs', label: '运行日志', subtitle: '环境 / 服务 / 插件日志', icon: 'view' as const, view: 'logs' },
      { id: 'settings', label: '环境与设置', subtitle: '工具链与偏好设置', icon: 'view' as const, view: 'settings' }
    ]
    for (const item of views) {
      if (matches(item.label, item.subtitle)) {
        result.push({
          kind: 'action',
          id: item.id,
          title: item.label,
          subtitle: item.subtitle,
          icon: 'view',
          view: item.view,
          action: () => appStore.setView(item.view as 'chat' | 'history' | 'plugins' | 'logs' | 'settings')
        })
      }
    }
    for (const session of snapshot.sessions.slice(0, 60)) {
      if (matches(session.displayTitle, session.projectName, session.workspacePath ?? '', session.id)) {
        result.push({ kind: 'session', session })
      }
    }
    return result.slice(0, 12)
  }, [query, snapshot.sessions, snapshot.webState.kind])

  const close = (): void => appStore.setPaletteOpen(false)
  const run = (entry: Entry): void => {
    if (entry.kind === 'action') entry.action()
    else {
      appStore.setView('chat')
      void window.api.web.openSession(entry.session.id, entry.session.displayTitle)
    }
    close()
  }

  return (
    <div className="fixed inset-0 z-50 bg-ink-950/30 backdrop-blur-[3px]" onMouseDown={close}>
      <div
        className="animate-scale-in mx-auto mt-[10vh] w-[620px] max-w-[calc(100vw-40px)] overflow-hidden rounded-2xl border border-ink-200 bg-white shadow-lifted dark:border-white/10 dark:bg-ink-900"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="flex items-center gap-3 border-b border-ink-200/70 px-4 py-3.5 dark:border-white/[0.06]">
          <Search size={18} className="text-brand-500" />
          <input
            ref={inputRef}
            autoFocus
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'Enter' && entries[0]) run(entries[0])
              if (event.key === 'Escape') close()
            }}
            placeholder="搜索会话、页面或操作…"
            className="min-w-0 flex-1 bg-transparent text-[15px] font-medium text-ink-900 outline-none placeholder:text-ink-300 dark:text-ink-50 dark:placeholder:text-ink-600"
          />
          <kbd className="rounded border border-ink-200 bg-ink-50 px-1.5 py-0.5 font-mono text-[10px] text-ink-400 dark:border-white/10 dark:bg-white/5">
            Esc
          </kbd>
        </div>

        <div className="max-h-[420px] overflow-y-auto p-2">
          {entries.length === 0 ? (
            <div className="py-10 text-center text-sm text-ink-400">没有匹配结果</div>
          ) : (
            entries.map((entry, index) => (
              <button
                key={entry.kind === 'action' ? entry.id : entry.session.id}
                onClick={() => run(entry)}
                className={`mb-0.5 flex w-full items-center gap-3 rounded-xl px-3 py-2.5 text-left transition hover:bg-brand-50 dark:hover:bg-brand-500/10 ${
                  index === 0 ? 'bg-ink-50 dark:bg-white/[0.04]' : ''
                }`}
              >
                <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-brand-100 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
                  {entry.kind === 'session' ? (
                    <MessageSquare size={14} />
                  ) : entry.icon === 'play' ? (
                    <Play size={14} />
                  ) : entry.icon === 'stop' ? (
                    <Square size={14} />
                  ) : entry.icon === 'sync' ? (
                    <RefreshCw size={14} />
                  ) : entry.view === 'plugins' ? (
                    <Blocks size={14} />
                  ) : entry.view === 'history' ? (
                    <History size={14} />
                  ) : entry.view === 'logs' ? (
                    <ScrollText size={14} />
                  ) : entry.view === 'settings' ? (
                    <Settings size={14} />
                  ) : (
                    <MessageSquare size={14} />
                  )}
                </span>
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[13px] font-semibold text-ink-900 dark:text-ink-50">
                    {entry.kind === 'action' ? entry.title : entry.session.displayTitle}
                  </span>
                  <span className="block truncate text-[11px] text-ink-500 dark:text-ink-400">
                    {entry.kind === 'action'
                      ? entry.subtitle
                      : `${entry.session.projectName} · ${entry.session.workspacePath ?? '未知工作区'} · ${relativeTime(entry.session.updatedAt)}`}
                  </span>
                </span>
                <span className="shrink-0 text-[10px] text-ink-300 dark:text-ink-600">
                  {entry.kind === 'action' ? '页面' : '会话'}
                </span>
              </button>
            ))
          )}
        </div>

        <div className="flex items-center gap-4 border-t border-ink-200/70 px-4 py-2.5 text-[10.5px] text-ink-400 dark:border-white/[0.06]">
          <span className="flex items-center gap-1"><kbd className="rounded bg-ink-100 px-1 font-mono dark:bg-white/5">↵</kbd> 执行首项</span>
          <span className="flex items-center gap-1"><kbd className="rounded bg-ink-100 px-1 font-mono dark:bg-white/5">Esc</kbd> 关闭</span>
          <span className="ml-auto">{entries.length} 项结果</span>
        </div>
      </div>
    </div>
  )
}
