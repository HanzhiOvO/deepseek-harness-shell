import { useMemo, useState } from 'react'
import { ArrowUpRight, Calendar, Clock, Copy, FolderOpen, Pin, PinOff, RefreshCw, Search } from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import { relativeTime } from '@shared/parsers'

type SortMode = 'updated' | 'created'

export default function HistoryView(): React.JSX.Element {
  const snapshot = useAppStore()
  const [query, setQuery] = useState('')
  const [pinnedOnly, setPinnedOnly] = useState(false)
  const [sort, setSort] = useState<SortMode>('updated')

  const sessions = useMemo(() => {
    const keyword = query.trim().toLowerCase()
    const result = snapshot.sessions.filter((session) => {
      if (pinnedOnly && !snapshot.settings?.pinnedSessionIds.includes(session.id)) return false
      if (!keyword) return true
      return [session.displayTitle, session.projectName, session.workspacePath ?? '', session.id]
        .some((value) => value.toLowerCase().includes(keyword))
    })
    result.sort((a, b) => {
      const av = sort === 'updated' ? (a.updatedAt ?? 0) : (a.createdAt ?? 0)
      const bv = sort === 'updated' ? (b.updatedAt ?? 0) : (b.createdAt ?? 0)
      return bv - av
    })
    return result
  }, [snapshot.sessions, snapshot.settings?.pinnedSessionIds, query, pinnedOnly, sort])

  return (
    <div className="flex h-full flex-col">
      <header className="shrink-0 border-b border-ink-200/70 bg-white/50 px-5 py-4 dark:border-white/[0.06] dark:bg-ink-900/30">
        <div className="flex items-center justify-between gap-4">
          <div>
            <h1 className="text-[17px] font-bold tracking-tight text-ink-900 dark:text-white">历史会话</h1>
            <p className="mt-0.5 text-[11px] text-ink-400">只读同步 DSH_HOME/sessions，与 Harness Web UI 使用同一份数据</p>
          </div>
          <div className="flex items-center gap-2">
            <span className="rounded-full bg-brand-50 px-2.5 py-1 text-[11px] font-semibold text-brand-700 dark:bg-brand-500/15 dark:text-brand-300">
              {sessions.length} 个会话
            </span>
            <button
              onClick={() => void window.api.sessions.sync()}
              className="flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-3 py-1.5 text-[11.5px] font-semibold text-white shadow-soft transition hover:brightness-110"
            >
              <RefreshCw size={12} /> 立即同步
            </button>
          </div>
        </div>

        <div className="mt-3 flex items-center gap-2">
          <div className="flex h-8 min-w-0 flex-1 items-center gap-2 rounded-lg border border-ink-200 bg-white px-2.5 shadow-soft dark:border-white/10 dark:bg-white/[0.04]">
            <Search size={13} className="shrink-0 text-ink-400" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="搜索标题、工作区、project 或会话 ID"
              className="min-w-0 flex-1 bg-transparent text-[12px] text-ink-900 outline-none placeholder:text-ink-300 dark:text-ink-50 dark:placeholder:text-ink-600"
            />
            {query && (
              <button onClick={() => setQuery('')} className="text-ink-300 hover:text-ink-500">
                ✕
              </button>
            )}
          </div>
          <button
            onClick={() => setPinnedOnly(!pinnedOnly)}
            className={`flex h-8 items-center gap-1.5 rounded-lg border px-2.5 text-[11.5px] font-medium shadow-soft transition ${
              pinnedOnly
                ? 'border-brand-300 bg-brand-50 text-brand-700 dark:border-brand-500/40 dark:bg-brand-500/15 dark:text-brand-300'
                : 'border-ink-200 bg-white text-ink-500 hover:border-brand-300 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-400'
            }`}
          >
            {pinnedOnly ? <Pin size={12} fill="currentColor" /> : <Pin size={12} />}
            {pinnedOnly ? '仅收藏' : '收藏'}
          </button>
          <select
            value={sort}
            onChange={(event) => setSort(event.target.value as SortMode)}
            className="h-8 rounded-lg border border-ink-200 bg-white px-2 text-[11.5px] font-medium text-ink-600 shadow-soft outline-none dark:border-white/10 dark:bg-ink-800 dark:text-ink-300"
          >
            <option value="updated">最近更新</option>
            <option value="created">创建时间</option>
          </select>
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto p-5">
        {snapshot.sessions.length === 0 ? (
          <EmptyState query="" />
        ) : sessions.length === 0 ? (
          <EmptyState query={query} />
        ) : (
          <div className="space-y-2">
            {sessions.map((session) => {
              const pinned = snapshot.settings?.pinnedSessionIds.includes(session.id) ?? false
              return (
                <article
                  key={session.id}
                  className="group rounded-xl border border-ink-200 bg-white/75 p-4 shadow-soft transition hover:-translate-y-px hover:border-brand-300 hover:shadow-lifted dark:border-white/[0.07] dark:bg-white/[0.04] dark:hover:border-brand-500/40"
                >
                  <div className="flex items-start gap-3">
                    <span className="mt-0.5 grid size-9 shrink-0 place-items-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
                      {pinned ? <Pin size={14} fill="currentColor" /> : <Calendar size={14} />}
                    </span>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start gap-2">
                        <h3 className="min-w-0 flex-1 truncate text-[13.5px] font-semibold text-ink-900 dark:text-ink-50">{session.displayTitle}</h3>
                        {pinned && (
                          <span className="rounded-full bg-brand-50 px-2 py-0.5 text-[9.5px] font-semibold text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
                            收藏
                          </span>
                        )}
                      </div>
                      <div className="mt-1 flex items-center gap-2 text-[10.5px] text-ink-400">
                        <span className="rounded bg-ink-100 px-1.5 py-0.5 font-medium dark:bg-white/[0.06]">{session.projectName}</span>
                        <span className="truncate font-mono">{session.id}</span>
                      </div>
                      <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-[10.5px] text-ink-500 dark:text-ink-400">
                        <span className="flex min-w-0 items-center gap-1"><FolderOpen size={11} className="shrink-0" /><span className="truncate">{session.workspacePath ?? '未知工作区'}</span></span>
                        <span className="flex items-center gap-1"><Calendar size={11} />{formatDate(session.createdAt)}</span>
                        <span className="flex items-center gap-1"><Clock size={11} />{relativeTime(session.updatedAt)}</span>
                      </div>
                    </div>
                    <div className="flex shrink-0 items-center gap-1 opacity-70 transition group-hover:opacity-100">
                      <IconButton title={pinned ? '取消收藏' : '收藏'} onClick={() => void window.api.sessions.togglePin(session.id)}>
                        {pinned ? <PinOff size={13} /> : <Pin size={13} />}
                      </IconButton>
                      <IconButton title="复制会话 ID" onClick={() => void copy(session.id)}>
                        <Copy size={13} />
                      </IconButton>
                      <IconButton title="在 Finder 中显示" onClick={() => void window.api.shell.reveal(session.filePath)}>
                        <FolderOpen size={13} />
                      </IconButton>
                      <button
                        onClick={() => {
                          appStore.setView('chat')
                          void window.api.web.openSession(session.id, session.displayTitle)
                        }}
                        className="ml-1 flex items-center gap-1 rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-2.5 py-1.5 text-[11px] font-semibold text-white shadow-soft transition hover:brightness-110"
                      >
                        打开 <ArrowUpRight size={11} />
                      </button>
                    </div>
                  </div>
                </article>
              )
            })}
          </div>
        )}
      </div>
    </div>
  )
}

function EmptyState({ query }: { query: string }): React.JSX.Element {
  return (
    <div className="grid h-full place-items-center">
      <div className="flex flex-col items-center text-center">
        <div className="grid size-14 place-items-center rounded-2xl bg-ink-100 text-ink-400 dark:bg-white/[0.06] dark:text-ink-500">
          <Search size={22} />
        </div>
        <h3 className="mt-4 text-[15px] font-semibold text-ink-700 dark:text-ink-200">
          {query ? '没有符合筛选条件的会话' : '没有找到本地历史会话'}
        </h3>
        <p className="mt-1.5 max-w-[380px] text-[11.5px] leading-relaxed text-ink-400">
          {query ? '试试更短的关键词，或清除搜索。' : '在 Harness 中开始新会话后会自动同步；应用回到前台也会自动刷新。'}
        </p>
        <button
          onClick={() => void window.api.sessions.sync()}
          className="mt-4 flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-3.5 py-2 text-[12px] font-semibold text-white shadow-soft hover:brightness-110"
        >
          <RefreshCw size={12} /> 立即同步
        </button>
      </div>
    </div>
  )
}

function IconButton({ children, onClick, title }: { children: React.ReactNode; onClick: () => void; title: string }): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      title={title}
      className="grid size-7.5 place-items-center rounded-lg text-ink-400 transition hover:bg-ink-100 hover:text-ink-700 dark:hover:bg-white/5 dark:hover:text-ink-200"
    >
      {children}
    </button>
  )
}

function formatDate(value: number | null): string {
  if (!value) return '创建时间未知'
  return `创建于 ${new Date(value).toLocaleString('zh-CN', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })}`
}

async function copy(value: string): Promise<void> {
  await navigator.clipboard.writeText(value)
  appStore.toast('已复制到剪贴板', 'success')
}
