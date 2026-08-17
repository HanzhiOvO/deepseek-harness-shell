import { useDeferredValue, useEffect, useMemo, useRef, useState } from 'react'
import {
  AlertTriangle,
  ArrowUpRight,
  CalendarDays,
  CheckCircle2,
  ChevronDown,
  ExternalLink,
  GitFork,
  LoaderCircle,
  PackagePlus,
  Palette,
  Search,
  Sparkles,
  Star,
  Store,
  WandSparkles
} from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import PluginSectionTabs from '../components/PluginSectionTabs'
import type { PluginSection } from '../components/PluginSectionTabs'
import {
  fetchMarketplaceRepositories,
  resolveMarketplaceInstallSpec,
  type MarketplaceKind,
  type MarketplaceRepository,
  type MarketplaceResult
} from '@shared/marketplace'

export default function MarketplaceView({ kind, onSectionChange }: { kind: MarketplaceKind; onSectionChange: (section: PluginSection) => void }): React.JSX.Element {
  const snapshot = useAppStore()
  const [repositories, setRepositories] = useState<MarketplaceRepository[]>([])
  const [totalCount, setTotalCount] = useState(0)
  const [page, setPage] = useState(0)
  const [query, setQuery] = useState('')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [installing, setInstalling] = useState<string | null>(null)
  const requestId = useRef(0)
  const controller = useRef<AbortController | null>(null)
  const deferredQuery = useDeferredValue(query)

  const load = async (nextPage: number, replace: boolean): Promise<void> => {
    controller.current?.abort()
    const currentController = new AbortController()
    controller.current = currentController
    const currentRequest = ++requestId.current
    setLoading(true)
    if (replace) setError(null)
    try {
      const result = await fetchMarketplaceRepositories(kind, nextPage, currentController.signal)
      if (currentRequest !== requestId.current) return
      applyResult(result, replace)
      setPage(nextPage)
      setError(null)
    } catch (loadError) {
      if (currentRequest !== requestId.current || isAbortError(loadError)) return
      setError(loadError instanceof Error ? loadError.message : String(loadError))
      if (replace) setRepositories([])
    } finally {
      if (currentRequest === requestId.current) setLoading(false)
    }
  }

  const applyResult = (result: MarketplaceResult, replace: boolean): void => {
    setRepositories((current) => (replace ? result.repositories : mergeRepositories(current, result.repositories)))
    setTotalCount(result.totalCount)
  }

  useEffect(() => {
    void load(1, true)
    return () => controller.current?.abort()
  }, [kind])

  const filteredRepositories = useMemo(() => {
    const keyword = deferredQuery.trim().toLowerCase()
    if (!keyword) return repositories
    return repositories.filter((repository) =>
      [repository.fullName, repository.description ?? '', repository.language ?? '', ...repository.topics]
        .join(' ')
        .toLowerCase()
        .includes(keyword)
    )
  }, [deferredQuery, repositories])

  const installedSkinPlugins = useMemo(
    () =>
      snapshot.plugins.filter(
        (plugin) => !plugin.isInbox && /skin|theme|style|ui/i.test(`${plugin.name} ${plugin.spec}`)
      ),
    [snapshot.plugins]
  )

  const install = async (repository: MarketplaceRepository): Promise<void> => {
    setInstalling(repository.fullName)
    try {
      const installSpec = await resolveMarketplaceInstallSpec(repository, kind)
      await window.api.plugins.install({ kind: 'github', githubText: installSpec })
      appStore.toast(
        kind === 'skins' ? `${repository.name} 已安装/修复，重启 Web UI 后生效` : `${repository.name} 已安装到当前 profile`,
        'success'
      )
    } catch (installError) {
      appStore.toast(installError instanceof Error ? installError.message : String(installError), 'error')
    } finally {
      setInstalling(null)
    }
  }

  const icon = kind === 'skins' ? <Palette size={18} /> : <Store size={18} />
  const title = kind === 'skins' ? '皮肤中心' : '插件市场'
  const subtitle = kind === 'skins' ? '发现 dsh 皮肤插件，安装后在 Web UI 内切换' : '从 GitHub dsh 话题发现社区插件'
  const hasMore = repositories.length < totalCount && page > 0
  const running = snapshot.webState.kind === 'running'

  return (
    <div className="flex h-full flex-col">
      <header className="shrink-0 border-b border-ink-200/70 bg-white/55 px-5 py-4 dark:border-white/[0.06] dark:bg-ink-900/35">
        <div className="flex flex-wrap items-start justify-between gap-4">
          <div className="flex items-start gap-3">
            <div className="grid size-10 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-brand-400 to-brand-800 text-white shadow-soft">
              {icon}
            </div>
            <div>
              <div className="mb-1 flex items-center gap-2 text-[9.5px] font-bold uppercase tracking-[0.18em] text-brand-500">
                <Sparkles size={11} /> GitHub topic index
              </div>
              <h1 className="text-[17px] font-bold tracking-tight text-ink-900 dark:text-white">{title}</h1>
              <p className="mt-0.5 text-[11px] text-ink-400">{subtitle}</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="rounded-full bg-brand-50 px-2.5 py-1 text-[11px] font-semibold text-brand-700 dark:bg-brand-500/15 dark:text-brand-300">
              {totalCount.toLocaleString('zh-CN')} 个候选
            </span>
            <button
              onClick={() => void load(1, true)}
              disabled={loading}
              className="grid size-8 place-items-center rounded-lg border border-ink-200 bg-white text-ink-500 shadow-soft transition hover:border-brand-300 hover:text-brand-600 disabled:cursor-not-allowed disabled:opacity-50 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-400"
              title="刷新 GitHub 市场"
            >
              <LoaderCircle size={14} className={loading ? 'animate-spin' : ''} />
            </button>
          </div>
        </div>

        <div className="mt-3 flex flex-wrap items-center gap-3">
          <PluginSectionTabs section={kind === 'skins' ? 'skins' : 'marketplace'} onChange={onSectionChange} />
          <div className="flex h-9 min-w-[220px] max-w-[560px] flex-1 items-center gap-2 rounded-lg border border-ink-200 bg-white px-2.5 shadow-soft dark:border-white/10 dark:bg-white/[0.04]">
            <Search size={14} className="shrink-0 text-ink-400" />
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder={kind === 'skins' ? '搜索皮肤、主题或作者…' : '搜索插件名称、功能或作者…'}
              className="min-w-0 flex-1 bg-transparent text-[12px] text-ink-900 outline-none placeholder:text-ink-300 dark:text-ink-50 dark:placeholder:text-ink-600"
            />
            {query && <span className="text-[10px] text-ink-300">{filteredRepositories.length} 项</span>}
          </div>
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto bg-ink-50/35 p-5 dark:bg-ink-950/25">
        {kind === 'skins' && (
          <SkinNotice installed={installedSkinPlugins.length} running={running} onOpen={() => void window.api.web.openWindow()} />
        )}

        {error && (
          <div className="mb-4 flex items-start gap-2 rounded-xl border border-amber-300/60 bg-amber-50 px-3.5 py-3 text-[11.5px] leading-relaxed text-amber-700 dark:border-amber-500/20 dark:bg-amber-500/10 dark:text-amber-300">
            <AlertTriangle size={14} className="mt-0.5 shrink-0" />
            <span className="flex-1">{error}</span>
            <button onClick={() => void load(1, true)} className="shrink-0 font-semibold underline underline-offset-2">重试</button>
          </div>
        )}

        {loading && repositories.length === 0 ? (
          <LoadingState kind={kind} />
        ) : filteredRepositories.length === 0 ? (
          <EmptyState kind={kind} hasQuery={Boolean(deferredQuery.trim())} onRefresh={() => void load(1, true)} />
        ) : (
          <>
            <div className="mb-3 flex items-center justify-between text-[10.5px] text-ink-400">
              <span>{deferredQuery.trim() ? `在已发现项目中筛选「${deferredQuery.trim()}」` : '按最近更新展示社区项目'}</span>
              {repositories.length < totalCount && <span>已加载 {repositories.length} / {totalCount.toLocaleString('zh-CN')}</span>}
            </div>
            <div className="grid grid-cols-1 gap-3 xl:grid-cols-2">
              {filteredRepositories.map((repository) => (
                <RepositoryCard
                  key={repository.id || repository.fullName}
                  repository={repository}
                  kind={kind}
                  installed={isRepositoryInstalled(repository, snapshot.plugins, kind)}
                  installing={installing === repository.fullName}
                  onInstall={() => void install(repository)}
                />
              ))}
            </div>
            {hasMore && (
              <button
                onClick={() => void load(page + 1, false)}
                disabled={loading}
                className="mx-auto mt-5 flex items-center gap-1.5 rounded-lg border border-ink-200 bg-white px-3.5 py-2 text-[11.5px] font-semibold text-ink-600 shadow-soft transition hover:border-brand-300 hover:text-brand-600 disabled:opacity-50 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300"
              >
                {loading ? <LoaderCircle size={13} className="animate-spin" /> : <ChevronDown size={13} />}
                加载更多
              </button>
            )}
          </>
        )}
      </div>
    </div>
  )
}

function SkinNotice({ installed, running, onOpen }: { installed: number; running: boolean; onOpen: () => void }): React.JSX.Element {
  return (
    <section className="mb-4 overflow-hidden rounded-2xl border border-brand-200/80 bg-gradient-to-br from-brand-50 via-white to-indigo-50/70 p-4 shadow-soft dark:border-brand-500/20 dark:from-brand-500/10 dark:via-ink-900/70 dark:to-indigo-500/10">
      <div className="flex flex-wrap items-center gap-3">
        <span className="grid size-9 place-items-center rounded-xl bg-brand-500 text-white shadow-soft"><WandSparkles size={17} /></span>
        <div className="min-w-[220px] flex-1">
          <h2 className="text-[13px] font-bold text-ink-900 dark:text-white">皮肤就是 dsh 插件</h2>
          <p className="mt-0.5 text-[10.5px] leading-relaxed text-ink-500 dark:text-ink-400">
            皮肤会安装到当前 profile，通过 dsh.client 注入 Web UI。安装完成后重启 Web UI，并在 dsh 的「设置 → 皮肤」中选择。
          </p>
        </div>
        <div className="flex items-center gap-2">
          <span className="rounded-full bg-white/80 px-2.5 py-1 text-[10px] font-semibold text-brand-700 dark:bg-white/[0.08] dark:text-brand-300">已识别 {installed} 个</span>
          <button
            onClick={onOpen}
            disabled={!running}
            className="flex items-center gap-1.5 rounded-lg bg-brand-500 px-2.5 py-1.5 text-[11px] font-semibold text-white transition hover:bg-brand-400 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <ExternalLink size={12} /> 打开 Web UI
          </button>
        </div>
      </div>
    </section>
  )
}

function RepositoryCard({
  repository,
  kind,
  installed,
  installing,
  onInstall
}: {
  repository: MarketplaceRepository
  kind: MarketplaceKind
  installed: boolean
  installing: boolean
  onInstall: () => void
}): React.JSX.Element {
  const installLabel = kind === 'skins' ? '安装皮肤' : '安装插件'
  return (
    <article className="group rounded-2xl border border-ink-200/80 bg-white/80 p-4 shadow-soft transition hover:-translate-y-px hover:border-brand-300 hover:shadow-lifted dark:border-white/[0.07] dark:bg-white/[0.04] dark:hover:border-brand-500/40">
      <div className="flex items-start gap-3">
        <div className="grid size-10 shrink-0 place-items-center rounded-xl bg-gradient-to-br from-brand-400 via-brand-600 to-indigo-900 text-white shadow-soft">
          {kind === 'skins' ? <Palette size={18} /> : <PackagePlus size={18} />}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <h3 className="truncate text-[13px] font-bold text-ink-900 dark:text-ink-50">{repository.name}</h3>
            {repository.archived && <Badge text="已归档" muted />}
            {repository.fork && <Badge text="Fork" muted />}
          </div>
          <div className="mt-0.5 truncate font-mono text-[10px] text-ink-400">{repository.fullName}</div>
        </div>
        <div className="flex shrink-0 items-center gap-1">
          <button
            onClick={() => void window.api.shell.openExternal(repository.htmlUrl)}
            className="grid size-7 place-items-center rounded-lg text-ink-400 transition hover:bg-ink-100 hover:text-brand-600 dark:hover:bg-white/5 dark:hover:text-brand-300"
            title="打开 GitHub 项目"
          >
            <ArrowUpRight size={14} />
          </button>
          <button
            onClick={onInstall}
            disabled={(installed && kind !== 'skins') || installing || repository.archived}
            className={`flex h-7 items-center gap-1 rounded-lg px-2.5 text-[10.5px] font-semibold transition disabled:cursor-not-allowed disabled:opacity-60 ${
              installed ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400' : 'bg-brand-500 text-white hover:bg-brand-400'
            }`}
          >
            {installing ? <LoaderCircle size={12} className="animate-spin" /> : installed ? <CheckCircle2 size={12} /> : null}
            {installed && kind !== 'skins' ? '已安装' : repository.archived ? '已归档' : installing ? '安装中' : installed ? '重装皮肤' : installLabel}
          </button>
        </div>
      </div>

      <p className="mt-3 line-clamp-3 min-h-[42px] text-[11.5px] leading-relaxed text-ink-500 dark:text-ink-400">
        {repository.description || '该项目没有提供描述，打开 GitHub 查看详细说明。'}
      </p>

      <div className="mt-3 flex flex-wrap gap-1">
        {repository.topics.slice(0, 6).map((topic) => <span key={topic} className="rounded-full bg-brand-50 px-2 py-0.5 text-[9.5px] font-medium text-brand-700 dark:bg-brand-500/10 dark:text-brand-300">#{topic}</span>)}
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-ink-100 pt-2.5 text-[10px] text-ink-400 dark:border-white/[0.05]">
        <span className="flex items-center gap-1"><Star size={11} /> {formatCount(repository.stars)}</span>
        <span className="flex items-center gap-1"><GitFork size={11} /> {formatCount(repository.forks)}</span>
        {repository.language && <span>{repository.language}</span>}
        {repository.license && <span>{repository.license}</span>}
        <span className="ml-auto flex items-center gap-1"><CalendarDays size={11} /> {formatDate(repository.updatedAt)}</span>
      </div>
    </article>
  )
}

function LoadingState({ kind }: { kind: MarketplaceKind }): React.JSX.Element {
  return (
    <div className="grid min-h-[360px] place-items-center">
      <div className="flex flex-col items-center text-center">
        <div className="grid size-14 place-items-center rounded-2xl bg-brand-50 text-brand-500 dark:bg-brand-500/15 dark:text-brand-300"><LoaderCircle size={24} className="animate-spin" /></div>
        <h2 className="mt-4 text-[14px] font-semibold text-ink-800 dark:text-ink-100">正在发现{kind === 'skins' ? '皮肤' : '插件'}…</h2>
        <p className="mt-1 text-[11px] text-ink-400">读取 GitHub 上的 dsh 话题项目</p>
      </div>
    </div>
  )
}

function EmptyState({ kind, hasQuery, onRefresh }: { kind: MarketplaceKind; hasQuery: boolean; onRefresh: () => void }): React.JSX.Element {
  return (
    <div className="grid min-h-[360px] place-items-center">
      <div className="flex max-w-[420px] flex-col items-center text-center">
        <div className="grid size-14 place-items-center rounded-2xl bg-ink-100 text-ink-400 dark:bg-white/[0.06] dark:text-ink-500"><Search size={23} /></div>
        <h2 className="mt-4 text-[14px] font-semibold text-ink-800 dark:text-ink-100">{hasQuery ? '没有匹配项目' : `暂时没有发现${kind === 'skins' ? '皮肤' : '插件'}`}</h2>
        <p className="mt-1.5 text-[11px] leading-relaxed text-ink-400">{hasQuery ? '尝试更短的关键词，或清除搜索。' : 'GitHub 话题索引可能受到 API 频率限制，请稍后刷新。'}</p>
        <button onClick={onRefresh} className="mt-4 rounded-lg bg-brand-500 px-3.5 py-2 text-[11.5px] font-semibold text-white hover:bg-brand-400">刷新市场</button>
      </div>
    </div>
  )
}

function Badge({ text, muted = false }: { text: string; muted?: boolean }): React.JSX.Element {
  return <span className={`rounded-full px-1.5 py-0.5 text-[9px] font-semibold ${muted ? 'bg-ink-100 text-ink-400 dark:bg-white/[0.06] dark:text-ink-500' : 'bg-brand-50 text-brand-600 dark:bg-brand-500/10 dark:text-brand-300'}`}>{text}</span>
}

function mergeRepositories(current: MarketplaceRepository[], next: MarketplaceRepository[]): MarketplaceRepository[] {
  const result = new Map(current.map((repository) => [repository.fullName, repository]))
  for (const repository of next) result.set(repository.fullName, repository)
  return [...result.values()]
}

function isRepositoryInstalled(
  repository: MarketplaceRepository,
  plugins: { name: string; spec: string }[],
  kind: MarketplaceKind
): boolean {
  const fullName = repository.fullName.toLowerCase()
  return plugins.some((plugin) => {
    const value = `${plugin.name} ${plugin.spec}`.toLowerCase()
    const sameRepository = value.includes(fullName)
    if (kind === 'skins') {
      return sameRepository && (value.includes('#path:') || /skin|theme/.test(plugin.name.toLowerCase()))
    }
    return sameRepository || plugin.name.toLowerCase() === repository.name.toLowerCase()
  })
}

function formatCount(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(1)}m`
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}k`
  return String(value)
}

function formatDate(value: string): string {
  if (!value) return '未知时间'
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? '未知时间' : date.toLocaleDateString('zh-CN', { month: 'short', day: 'numeric' })
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException && error.name === 'AbortError'
}
