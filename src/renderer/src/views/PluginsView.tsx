import { useMemo, useState } from 'react'
import {
  Blocks,
  Download,
  FileArchive,
  FolderOpen,
  FolderPlus,
  GitBranch as GithubIcon,
  Globe,
  Package,
  Plus,
  RefreshCw,
  Search,
  Trash2
} from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import InstallPluginModal, { type InstallDraftState } from '../components/InstallPluginModal'
import type { InstalledPlugin } from '@shared/types'

export default function PluginsView(): React.JSX.Element {
  const snapshot = useAppStore()
  const [query, setQuery] = useState('')
  const [modal, setModal] = useState<InstallDraftState | null>(null)
  const [dragOver, setDragOver] = useState(false)
  const [confirmRemove, setConfirmRemove] = useState<InstalledPlugin | null>(null)
  const [confirmUpdate, setConfirmUpdate] = useState<InstalledPlugin | null>(null)

  const plugins = useMemo(() => {
    const keyword = query.trim().toLowerCase()
    if (!keyword) return snapshot.plugins
    return snapshot.plugins.filter(
      (plugin) => plugin.name.toLowerCase().includes(keyword) || plugin.spec.toLowerCase().includes(keyword)
    )
  }, [snapshot.plugins, query])

  const onDrop = (event: React.DragEvent): void => {
    event.preventDefault()
    setDragOver(false)
    const file = event.dataTransfer.files[0]
    if (!file) return
    const path = window.api.shell.pathForFile(file)
    if (!path) return
    if (path.toLowerCase().endsWith('.zip')) setModal({ kind: 'zip', filePath: path })
    else setModal({ kind: 'folder', filePath: path })
  }

  return (
    <div className="relative flex h-full flex-col" onDragOver={(event) => { event.preventDefault(); setDragOver(true) }} onDragLeave={() => setDragOver(false)} onDrop={onDrop}>
      <header className="shrink-0 border-b border-ink-200/70 bg-white/50 px-5 py-4 dark:border-white/[0.06] dark:bg-ink-900/30">
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="grid size-10 place-items-center rounded-xl bg-gradient-to-br from-brand-400 to-brand-800 text-white shadow-soft">
              <Blocks size={17} />
            </div>
            <div>
              <h1 className="text-[17px] font-bold tracking-tight text-ink-900 dark:text-white">插件中心</h1>
              <p className="mt-0.5 text-[11px] text-ink-400">通过 dsh plugin 安装进 profile，自动 reconcile bundle 层</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <span className="rounded-full bg-brand-50 px-2.5 py-1 text-[11px] font-semibold text-brand-700 dark:bg-brand-500/15 dark:text-brand-300">
              {plugins.length} 个插件
            </span>
            <select
              value={snapshot.settings?.profileName ?? 'web'}
              onChange={(event) => void window.api.plugins.setProfile(event.target.value)}
              className="h-8 rounded-lg border border-ink-200 bg-white px-2 text-[11.5px] font-medium text-ink-600 shadow-soft outline-none dark:border-white/10 dark:bg-ink-800 dark:text-ink-300"
              title="选择 profile"
            >
              {snapshot.profiles.map((profile) => (
                <option key={profile} value={profile}>{profile}</option>
              ))}
            </select>
            <button
              onClick={() => void window.api.plugins.refresh()}
              className="grid size-8 place-items-center rounded-lg border border-ink-200 bg-white text-ink-500 shadow-soft transition hover:border-brand-300 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-400"
              title="刷新插件清单"
            >
              <RefreshCw size={13} />
            </button>
            <button
              onClick={() => setModal({ kind: 'github' })}
              className="flex h-8 items-center gap-1.5 rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-3 text-[11.5px] font-semibold text-white shadow-soft transition hover:brightness-110"
            >
              <Plus size={13} /> 安装插件
            </button>
          </div>
        </div>

        <div className="mt-3 flex h-8 min-w-0 max-w-[420px] items-center gap-2 rounded-lg border border-ink-200 bg-white px-2.5 shadow-soft dark:border-white/10 dark:bg-white/[0.04]">
          <Search size={13} className="shrink-0 text-ink-400" />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="搜索插件名称或安装 spec"
            className="min-w-0 flex-1 bg-transparent text-[12px] text-ink-900 outline-none placeholder:text-ink-300 dark:text-ink-50 dark:placeholder:text-ink-600"
          />
        </div>
      </header>

      <div className="min-h-0 flex-1 overflow-y-auto p-5">
        {plugins.length === 0 ? (
          <EmptyPlugins hasQuery={Boolean(query)} onInstall={() => setModal({ kind: 'github' })} />
        ) : (
          <div className="grid grid-cols-1 gap-2 xl:grid-cols-2">
            {plugins.map((plugin) => (
              <PluginCard
                key={plugin.name}
                plugin={plugin}
                onUpdate={() => setConfirmUpdate(plugin)}
                onRemove={() => setConfirmRemove(plugin)}
              />
            ))}
          </div>
        )}
      </div>

      {dragOver && (
        <div className="pointer-events-none absolute inset-3 z-20 grid place-items-center rounded-2xl border-2 border-dashed border-brand-400 bg-brand-500/10 backdrop-blur-[2px]">
          <div className="flex flex-col items-center gap-2 text-brand-600 dark:text-brand-300">
            <Download size={34} />
            <div className="text-[15px] font-semibold">松开以安装插件</div>
            <div className="text-[11px] text-brand-500/80 dark:text-brand-300/70">支持 .zip 压缩包或包含 package.json 的文件夹</div>
          </div>
        </div>
      )}

      {modal && <InstallPluginModal draft={modal} onClose={() => setModal(null)} />}

      {confirmRemove && (
        <ConfirmModal
          title={`移除插件 ${confirmRemove.name}`}
          message={`等价于 dsh plugin --profile ${snapshot.settings?.profileName ?? 'web'} remove，不会删除本地源文件。`}
          confirmText="移除"
          danger
          onCancel={() => setConfirmRemove(null)}
          onConfirm={() => {
            const name = confirmRemove.name
            setConfirmRemove(null)
            void window.api.plugins.remove(name).then(
              () => appStore.toast(`已移除 ${name}`, 'success'),
              (error) => appStore.toast(String(error.message ?? error), 'error')
            )
          }}
        />
      )}

      {confirmUpdate && (
        <ConfirmModal
          title={`更新插件 ${confirmUpdate.name}`}
          message="npm 源将升级到 latest；GitHub / 本地目录源按 package.json 中的原 spec 重新解析。"
          confirmText="更新到最新"
          onCancel={() => setConfirmUpdate(null)}
          onConfirm={() => {
            const name = confirmUpdate.name
            setConfirmUpdate(null)
            void window.api.plugins.update(name).then(
              () => appStore.toast(`${name} 更新完成`, 'success'),
              (error) => appStore.toast(String(error.message ?? error), 'error')
            )
          }}
        />
      )}
    </div>
  )
}

function PluginCard({
  plugin,
  onUpdate,
  onRemove
}: {
  plugin: InstalledPlugin
  onUpdate: () => void
  onRemove: () => void
}): React.JSX.Element {
  const icon = plugin.sourceKind === 'github' ? <GithubIcon size={17} /> : plugin.sourceKind === 'zip' ? <FileArchive size={17} /> : plugin.sourceKind === 'folder' ? <FolderOpen size={17} /> : <Package size={17} />

  return (
    <article className="group rounded-xl border border-ink-200 bg-white/75 p-4 shadow-soft transition hover:-translate-y-px hover:border-brand-300 hover:shadow-lifted dark:border-white/[0.07] dark:bg-white/[0.04] dark:hover:border-brand-500/40">
      <div className="flex items-start gap-3">
        <span className={`grid size-10 shrink-0 place-items-center rounded-xl text-white shadow-soft ${plugin.isInbox ? 'bg-gradient-to-br from-indigo-500 to-indigo-800' : 'bg-gradient-to-br from-brand-400 to-brand-800'}`}>
          {icon}
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <h3 className="truncate text-[13px] font-semibold text-ink-900 dark:text-ink-50">{plugin.name}</h3>
            {plugin.isInbox && <Tag text="内置" color="text-indigo-600 dark:text-indigo-400 bg-indigo-500/10" />}
            {plugin.isBundle && !plugin.isInbox && <Tag text="BUNDLE" color="text-brand-600 dark:text-brand-400 bg-brand-500/10" />}
            <Tag
              text={sourceLabel(plugin.sourceKind)}
              color={plugin.isInbox ? 'text-ink-500 dark:text-ink-400 bg-ink-100 dark:bg-white/[0.06]' : 'text-ink-600 dark:text-ink-300 bg-ink-100 dark:bg-white/[0.06]'}
            />
          </div>
          <div className="mt-1 truncate font-mono text-[10.5px] text-ink-400" title={plugin.spec}>{plugin.spec}</div>
          {plugin.version && <div className="mt-0.5 text-[10px] font-medium text-ink-300 dark:text-ink-500">v{plugin.version}</div>}
        </div>
        {!plugin.isInbox && (
          <div className="flex shrink-0 items-center gap-1 opacity-60 transition group-hover:opacity-100">
            {plugin.externalUrl && (
              <IconButton title="打开插件主页" onClick={() => void window.api.shell.openExternal(plugin.externalUrl!)}>
                <Globe size={13} />
              </IconButton>
            )}
            {plugin.localSource && (
              <IconButton title="在 Finder 中显示源码" onClick={() => void window.api.shell.reveal(plugin.localSource!)}>
                <FolderOpen size={13} />
              </IconButton>
            )}
            <IconButton title="更新插件" onClick={onUpdate}>
              <RefreshCw size={13} />
            </IconButton>
            <IconButton title="移除插件" onClick={onRemove} danger>
              <Trash2 size={13} />
            </IconButton>
          </div>
        )}
        {plugin.isInbox && (
          <span className="shrink-0 rounded-full bg-ink-100 px-2 py-1 text-[10px] text-ink-400 dark:bg-white/[0.05]" title="内置 bundle，随 dsh 一起升级">
            随附
          </span>
        )}
      </div>
    </article>
  )
}

function EmptyPlugins({ hasQuery, onInstall }: { hasQuery: boolean; onInstall: () => void }): React.JSX.Element {
  return (
    <div className="grid h-full place-items-center">
      <div className="flex flex-col items-center text-center">
        <div className="grid size-14 place-items-center rounded-2xl bg-brand-50 text-brand-500 dark:bg-brand-500/15 dark:text-brand-300">
          <FolderPlus size={24} />
        </div>
        <h3 className="mt-4 text-[15px] font-semibold text-ink-700 dark:text-ink-200">{hasQuery ? '没有匹配的插件' : '这个 profile 还没有插件'}</h3>
        <p className="mt-1.5 max-w-[420px] text-[11.5px] leading-relaxed text-ink-400">
          {hasQuery ? '清除搜索后再试。' : '支持 GitHub 仓库、ZIP 压缩包、本地文件夹与 npm 包名四种安装方式，也可以直接把 .zip / 文件夹拖进窗口。'}
        </p>
        {!hasQuery && (
          <button onClick={onInstall} className="mt-4 flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-3.5 py-2 text-[12px] font-semibold text-white shadow-soft hover:brightness-110">
            <Plus size={13} /> 安装第一个插件
          </button>
        )}
      </div>
    </div>
  )
}

function ConfirmModal({
  title,
  message,
  confirmText,
  danger = false,
  onCancel,
  onConfirm
}: {
  title: string
  message: string
  confirmText: string
  danger?: boolean
  onCancel: () => void
  onConfirm: () => void
}): React.JSX.Element {
  return (
    <div className="fixed inset-0 z-40 grid place-items-center bg-ink-950/35 p-6 backdrop-blur-sm" onMouseDown={onCancel}>
      <div className="animate-scale-in w-full max-w-[420px] rounded-2xl border border-ink-200 bg-white p-5 shadow-lifted dark:border-white/10 dark:bg-ink-900" onMouseDown={(event) => event.stopPropagation()}>
        <h3 className="text-[15px] font-semibold text-ink-900 dark:text-white">{title}</h3>
        <p className="mt-2 text-[12px] leading-relaxed text-ink-500 dark:text-ink-400">{message}</p>
        <div className="mt-5 flex justify-end gap-2">
          <button onClick={onCancel} className="rounded-lg border border-ink-200 bg-white px-3.5 py-1.5 text-[12px] font-medium text-ink-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300">
            取消
          </button>
          <button
            onClick={onConfirm}
            className={`rounded-lg px-3.5 py-1.5 text-[12px] font-semibold text-white shadow-soft ${
              danger ? 'bg-red-500 hover:bg-red-600' : 'bg-gradient-to-br from-brand-400 to-brand-700 hover:brightness-110'
            }`}
          >
            {confirmText}
          </button>
        </div>
      </div>
    </div>
  )
}

function Tag({ text, color }: { text: string; color: string }): React.JSX.Element {
  return <span className={`rounded-full px-2 py-0.5 text-[9.5px] font-semibold ${color}`}>{text}</span>
}

function IconButton({
  children,
  onClick,
  title,
  danger = false
}: {
  children: React.ReactNode
  onClick: () => void
  title: string
  danger?: boolean
}): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      title={title}
      className={`grid size-7.5 place-items-center rounded-lg transition ${
        danger
          ? 'text-ink-400 hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-500/10 dark:hover:text-red-400'
          : 'text-ink-400 hover:bg-ink-100 hover:text-ink-700 dark:hover:bg-white/5 dark:hover:text-ink-200'
      }`}
    >
      {children}
    </button>
  )
}

function sourceLabel(kind: InstalledPlugin['sourceKind']): string {
  if (kind === 'github') return 'GitHub'
  if (kind === 'zip') return '归档'
  if (kind === 'folder') return '本地目录'
  return 'npm'
}

export type { InstallDraftState }
