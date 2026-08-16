import {
  Blocks,
  History,
  MessageSquare,
  Pin,
  RefreshCw,
  ScrollText,
  Search,
  Settings,
  TerminalSquare
} from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import { relativeTime } from '@shared/parsers'

const NAV_ITEMS = [
  { id: 'chat', label: '对话', icon: MessageSquare },
  { id: 'history', label: '历史会话', icon: History },
  { id: 'plugins', label: '插件中心', icon: Blocks },
  { id: 'logs', label: '运行日志', icon: ScrollText },
  { id: 'settings', label: '环境与设置', icon: Settings }
] as const

export default function Sidebar(): React.JSX.Element {
  const snapshot = useAppStore()
  const pinned = snapshot.sessions.filter((session) => snapshot.settings?.pinnedSessionIds.includes(session.id) ?? false)
  const recent = snapshot.sessions.slice(0, 30)

  return (
    <aside className="flex w-[260px] shrink-0 flex-col border-r border-ink-200/70 bg-white/60 dark:border-white/[0.06] dark:bg-ink-900/40">
      <div className="app-drag flex h-14 shrink-0 items-center gap-2.5 px-3.5">
        <div className="grid size-8 place-items-center rounded-[10px] bg-gradient-to-br from-brand-400 to-brand-900 text-white shadow-soft">
          <TerminalSquare size={14} strokeWidth={2.2} />
        </div>
        <div className="leading-tight">
          <div className="text-[13px] font-semibold tracking-tight">DeepSeek Harness</div>
          <div className="text-[10.5px] font-medium text-ink-400">Shell · v{snapshot.appVersion}</div>
        </div>
      </div>

      <div className="app-no-drag px-3 pb-2">
        <button
          onClick={() => appStore.setPaletteOpen(true)}
          className="flex h-8 w-full items-center gap-2 rounded-lg border border-ink-200 bg-ink-50 px-2.5 text-[11.5px] text-ink-500 shadow-soft transition hover:border-brand-300 hover:bg-white hover:text-brand-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-400 dark:hover:border-brand-500/40 dark:hover:bg-white/[0.07] dark:hover:text-brand-300"
        >
          <Search size={13} />
          <span className="flex-1 text-left">搜索会话或功能</span>
          <kbd className="rounded border border-ink-200 bg-white px-1 font-mono text-[9.5px] dark:border-white/10 dark:bg-white/5">⌘K</kbd>
        </button>
      </div>

      <nav className="app-no-drag px-2.5">
        {NAV_ITEMS.map((item) => {
          const active = snapshot.view === item.id
          const Icon = item.icon
          return (
            <button
              key={item.id}
              onClick={() => appStore.setView(item.id)}
              className={`mb-0.5 flex h-8 w-full items-center gap-2.5 rounded-lg px-2.5 text-[12.5px] font-medium transition ${
                active
                  ? 'bg-brand-50 text-brand-700 shadow-soft dark:bg-brand-500/15 dark:text-brand-200'
                  : 'text-ink-600 hover:bg-ink-100/80 hover:text-ink-900 dark:text-ink-400 dark:hover:bg-white/5 dark:hover:text-ink-50'
              }`}
            >
              <Icon size={15} strokeWidth={active ? 2.4 : 2} />
              <span className="flex-1 text-left">{item.label}</span>
              {item.id === 'plugins' && snapshot.plugins.length > 2 && (
                <span className="rounded-full bg-ink-100 px-1.5 text-[9.5px] text-ink-500 dark:bg-white/10 dark:text-ink-400">
                  {snapshot.plugins.length}
                </span>
              )}
            </button>
          )
        })}
      </nav>

      <div className="app-no-drag mt-4 min-h-0 flex-1 overflow-y-auto px-3">
        {pinned.length > 0 && (
          <section className="mb-3">
            <div className="mb-1.5 flex items-center gap-1.5 px-1 text-[10px] font-semibold uppercase tracking-wider text-ink-400">
              <Pin size={10} /> 收藏
            </div>
            {pinned.slice(0, 6).map((session) => (
              <SessionRow key={session.id} session={session} pinned />
            ))}
          </section>
        )}

        <section>
          <div className="mb-1.5 flex items-center justify-between px-1">
            <span className="text-[10px] font-semibold uppercase tracking-wider text-ink-400">最近会话</span>
            <button
              onClick={() => void window.api.sessions.sync()}
              className="grid size-5 place-items-center rounded text-ink-400 transition hover:bg-ink-100 hover:text-ink-700 dark:hover:bg-white/5 dark:hover:text-ink-200"
              title="同步会话"
            >
              <RefreshCw size={11} />
            </button>
          </div>
          {recent.length === 0 ? (
            <div className="px-1 py-3 text-[11px] leading-relaxed text-ink-400">暂无本地会话。启动 Harness 并开始对话后会自动同步。</div>
          ) : (
            recent.map((session) => <SessionRow key={session.id} session={session} pinned={false} />)
          )}
        </section>
      </div>

      <div className="app-no-drag shrink-0 border-t border-ink-200/70 p-3 dark:border-white/[0.06]">
        <StatusRow label={snapshot.envState?.label ?? '环境检测中'} color={envColor(snapshot.envState?.kind)} />
        <StatusRow label={webLabel(snapshot.webState.kind)} color={webColor(snapshot.webState.kind)} />
        <div className="mt-1.5 text-[10px] text-ink-400">
          会话 {snapshot.sessions.length} 个
          {snapshot.settings?.profileName ? ` · profile ${snapshot.settings.profileName}` : ''}
        </div>
      </div>
    </aside>
  )
}

function SessionRow({ session, pinned }: { session: import('@shared/types').SessionSummary; pinned: boolean }): React.JSX.Element {
  return (
    <button
      onClick={() => {
        appStore.setView('chat')
        void window.api.web.openSession(session.id, session.displayTitle)
      }}
      className="group mb-0.5 block w-full rounded-lg px-2 py-1.5 text-left transition hover:bg-ink-100/80 dark:hover:bg-white/5"
    >
      <div className="flex items-start gap-1.5">
        <span className="mt-[3px] size-1.5 shrink-0 rounded-full bg-brand-300 group-hover:bg-brand-500" />
        <span className="line-clamp-2 text-[11.5px] font-medium leading-snug text-ink-700 dark:text-ink-200">{session.displayTitle}</span>
        {pinned && <Pin size={9} className="mt-1 shrink-0 text-brand-500" fill="currentColor" />}
      </div>
      <div className="mt-0.5 flex items-center gap-1.5 pl-3 text-[10px] text-ink-400">
        <span className="truncate">{session.projectName}</span>
        <span>·</span>
        <span className="shrink-0">{relativeTime(session.updatedAt)}</span>
      </div>
    </button>
  )
}

function StatusRow({ label, color }: { label: string; color: string }): React.JSX.Element {
  return (
    <div className="mb-1 flex items-center gap-2 text-[10.5px] text-ink-500 dark:text-ink-400">
      <span className={`size-1.5 rounded-full ${color}`} />
      <span className="truncate">{label}</span>
    </div>
  )
}

function envColor(kind: string | undefined): string {
  if (kind === 'ready') return 'bg-emerald-500'
  if (kind === 'checking' || kind === 'installing' || kind === 'idle') return 'bg-amber-500 animate-soft-pulse'
  if (kind === 'missing-dsh' || kind === 'missing-node' || kind === 'missing-npm' || kind === 'failed') return 'bg-red-500'
  return 'bg-ink-300 dark:bg-ink-600'
}

function webLabel(kind: string): string {
  if (kind === 'running') return 'Web UI 运行中'
  if (kind === 'starting') return 'Web UI 启动中'
  if (kind === 'failed') return 'Web UI 异常'
  return 'Web UI 未启动'
}

function webColor(kind: string): string {
  if (kind === 'running') return 'bg-emerald-500'
  if (kind === 'starting') return 'bg-amber-500 animate-soft-pulse'
  if (kind === 'failed') return 'bg-red-500'
  return 'bg-ink-300 dark:bg-ink-600'
}
