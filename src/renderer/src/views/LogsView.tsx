import { useMemo, useState } from 'react'
import { Download, Search, Trash2 } from 'lucide-react'
import { useAppStore } from '../state/store'
import type { LogEntry, LogLevel, LogSource } from '@shared/types'

type SourceFilter = 'all' | LogSource

const SOURCES: { id: SourceFilter; label: string }[] = [
  { id: 'all', label: '全部' },
  { id: 'environment', label: '环境' },
  { id: 'web', label: 'Web 服务' },
  { id: 'plugins', label: '插件' },
  { id: 'sessions', label: '会话' }
]

const LEVELS: { id: LogLevel; label: string }[] = [
  { id: 'info', label: '信息' },
  { id: 'command', label: '命令' },
  { id: 'stdout', label: '标准输出' },
  { id: 'stderr', label: '标准错误' },
  { id: 'warning', label: '警告' },
  { id: 'error', label: '错误' },
  { id: 'success', label: '成功' }
]

export default function LogsView(): React.JSX.Element {
  const snapshot = useAppStore()
  const [source, setSource] = useState<SourceFilter>('all')
  const [level, setLevel] = useState<LogLevel | 'all'>('all')
  const [query, setQuery] = useState('')

  const entries = useMemo(() => {
    const sources: LogSource[] = source === 'all' ? ['environment', 'web', 'plugins', 'sessions'] : [source]
    const keyword = query.trim().toLowerCase()
    return sources
      .flatMap((item) => snapshot.logs[item])
      .filter((entry) => {
        if (level !== 'all' && entry.level !== level) return false
        if (keyword && !entry.text.toLowerCase().includes(keyword)) return false
        return true
      })
      .sort((a, b) => a.date - b.date)
  }, [snapshot.logs, source, level, query])

  const exportLogs = async (): Promise<void> => {
    const text = entries
      .map((entry) => `[${new Date(entry.date).toISOString()}] [${entry.source}/${entry.level}] ${entry.text}`)
      .join('\n')
    await window.api.logs.export(text, `deepseek-harness-shell-logs-${new Date().toISOString().slice(0, 10)}.txt`)
  }

  return (
    <div className="flex h-full flex-col">
      <header className="shrink-0 border-b border-ink-200/70 bg-white/50 px-5 py-4 dark:border-white/[0.06] dark:bg-ink-900/30">
        <div className="flex items-center justify-between gap-3">
          <div>
            <h1 className="text-[17px] font-bold tracking-tight text-ink-900 dark:text-white">运行日志</h1>
            <p className="mt-0.5 text-[11px] text-ink-400">按来源与级别筛选，共 {entries.length} 条</p>
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => void exportLogs()}
              className="flex items-center gap-1.5 rounded-lg border border-ink-200 bg-white px-3 py-1.5 text-[11.5px] font-medium text-ink-600 shadow-soft transition hover:border-brand-300 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300"
            >
              <Download size={12} /> 导出
            </button>
            <button
              onClick={() => void window.api.logs.clear(source === 'all' ? undefined : source)}
              className="flex items-center gap-1.5 rounded-lg border border-ink-200 bg-white px-3 py-1.5 text-[11.5px] font-medium text-ink-600 shadow-soft transition hover:border-red-300 hover:text-red-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300 dark:hover:text-red-400"
            >
              <Trash2 size={12} /> 清空
            </button>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-2">
          <div className="flex items-center gap-0.5 rounded-lg bg-ink-100 p-0.5 dark:bg-white/[0.05]">
            {SOURCES.map((item) => (
              <button
                key={item.id}
                onClick={() => setSource(item.id)}
                className={`rounded-md px-2.5 py-1.5 text-[11px] font-semibold transition ${
                  source === item.id
                    ? 'bg-white text-brand-700 shadow-soft dark:bg-ink-800 dark:text-brand-300'
                    : 'text-ink-500 hover:text-ink-800 dark:text-ink-400 dark:hover:text-ink-100'
                }`}
              >
                {item.label}
              </button>
            ))}
          </div>

          <select
            value={level}
            onChange={(event) => setLevel(event.target.value as LogLevel | 'all')}
            className="h-8 rounded-lg border border-ink-200 bg-white px-2 text-[11.5px] font-medium text-ink-600 shadow-soft outline-none dark:border-white/10 dark:bg-ink-800 dark:text-ink-300"
          >
            <option value="all">全部级别</option>
            {LEVELS.map((item) => (
              <option key={item.id} value={item.id}>{item.label}</option>
            ))}
          </select>

          <div className="flex h-8 min-w-[220px] flex-1 items-center gap-2 rounded-lg border border-ink-200 bg-white px-2.5 shadow-soft dark:border-white/10 dark:bg-white/[0.04]">
            <Search size={13} className="shrink-0 text-ink-400" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="搜索日志内容"
              className="min-w-0 flex-1 bg-transparent text-[12px] text-ink-900 outline-none placeholder:text-ink-300 dark:text-ink-50 dark:placeholder:text-ink-600"
            />
          </div>
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto bg-ink-50/60 p-4 dark:bg-ink-950/50">
        {entries.length === 0 ? (
          <div className="grid h-full place-items-center text-[12px] text-ink-400">当前筛选条件下没有日志</div>
        ) : (
          <div className="space-y-0.5 rounded-xl border border-ink-200/70 bg-white/80 p-2.5 font-mono dark:border-white/[0.06] dark:bg-ink-900/60">
            {entries.map((entry) => (
              <LogRow key={entry.id} entry={entry} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

function LogRow({ entry }: { entry: LogEntry }): React.JSX.Element {
  const color =
    entry.level === 'error'
      ? 'text-red-500'
      : entry.level === 'warning' || entry.level === 'stderr'
        ? 'text-amber-500'
        : entry.level === 'success'
          ? 'text-emerald-500'
          : entry.level === 'command'
            ? 'text-brand-500'
            : 'text-ink-700 dark:text-ink-300'

  return (
    <div className="flex items-start gap-2 rounded-md px-2 py-1 text-[10.5px] leading-relaxed hover:bg-ink-50 dark:hover:bg-white/[0.03]">
      <span className="shrink-0 text-ink-300 dark:text-ink-600">{new Date(entry.date).toLocaleTimeString('zh-CN', { hour12: false })}</span>
      <span className="shrink-0 rounded bg-ink-100 px-1 text-[9px] text-ink-400 dark:bg-white/[0.06] dark:text-ink-500">
        {entry.source === 'environment' ? 'ENV' : entry.source === 'web' ? 'WEB' : entry.source === 'plugins' ? 'PLUG' : 'SES'}
      </span>
      <span className={`min-w-0 break-all ${color}`}>{entry.text}</span>
    </div>
  )
}
