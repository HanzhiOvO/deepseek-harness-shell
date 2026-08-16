import { useEffect, useState } from 'react'
import { CheckCircle2, FileArchive, FolderOpen, GitBranch as GithubIcon, Package, X } from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import { parseGitHubSpec } from '@shared/parsers'
import type { InstallKind } from '@shared/types'

export interface InstallDraftState {
  kind: InstallKind
  githubText?: string
  npmText?: string
  filePath?: string
}

const KINDS: { id: InstallKind; label: string; icon: React.ReactNode }[] = [
  { id: 'github', label: 'GitHub 仓库', icon: <GithubIcon size={13} /> },
  { id: 'zip', label: 'ZIP 压缩包', icon: <FileArchive size={13} /> },
  { id: 'folder', label: '本地文件夹', icon: <FolderOpen size={13} /> },
  { id: 'npm', label: 'npm 包', icon: <Package size={13} /> }
]

export default function InstallPluginModal({ draft, onClose }: { draft: InstallDraftState; onClose: () => void }): React.JSX.Element {
  const snapshot = useAppStore()
  const [kind, setKind] = useState<InstallKind>(draft.kind)
  const [githubText, setGithubText] = useState(draft.githubText ?? '')
  const [npmText, setNpmText] = useState(draft.npmText ?? '')
  const [filePath, setFilePath] = useState(draft.filePath ?? '')
  const [running, setRunning] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const githubPreview = ((): string | null => {
    try {
      const parsed = parseGitHubSpec(githubText)
      return `将安装 github:${parsed.owner}/${parsed.repository}${parsed.ref ? `#${parsed.ref}` : ''}`
    } catch {
      return null
    }
  })()

  useEffect(() => {
    if (kind === 'github' && !githubText) {
      void navigator.clipboard.readText().then((text) => {
        if (text.includes('github.com') && parseGitHubSpec(text.trim())) setGithubText(text.trim())
      }).catch(() => undefined)
    }
  }, [kind, githubText])

  const install = async (): Promise<void> => {
    setRunning(true)
    setError(null)
    try {
      await window.api.plugins.install({
        kind,
        githubText: kind === 'github' ? githubText : undefined,
        npmText: kind === 'npm' ? npmText : undefined,
        filePath: kind === 'zip' || kind === 'folder' ? filePath : undefined
      })
      appStore.toast('插件安装完成', 'success')
      onClose()
    } catch (installError) {
      setError(installError instanceof Error ? installError.message : String(installError))
    } finally {
      setRunning(false)
    }
  }

  const logs = snapshot.logs.plugins.slice(-8)

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-ink-950/35 p-6 backdrop-blur-sm" onMouseDown={onClose}>
      <div
        className="animate-scale-in flex max-h-[86vh] w-full max-w-[620px] flex-col rounded-2xl border border-ink-200 bg-white shadow-lifted dark:border-white/10 dark:bg-ink-900"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="flex items-start justify-between border-b border-ink-200/70 px-5 py-4 dark:border-white/[0.06]">
          <div>
            <h2 className="text-[16px] font-bold text-ink-900 dark:text-white">安装插件</h2>
            <p className="mt-0.5 text-[11px] text-ink-400">安装到 profile「{snapshot.settings?.profileName ?? 'web'}」· 插件是本地代码，只安装信任来源</p>
          </div>
          <button onClick={onClose} className="grid size-7 place-items-center rounded-lg text-ink-400 hover:bg-ink-100 dark:hover:bg-white/5">
            <X size={15} />
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto p-5">
          <div className="grid grid-cols-4 gap-1 rounded-xl bg-ink-100 p-1 dark:bg-white/[0.05]">
            {KINDS.map((item) => (
              <button
                key={item.id}
                onClick={() => setKind(item.id)}
                className={`flex items-center justify-center gap-1.5 rounded-lg px-2 py-2 text-[11.5px] font-semibold transition ${
                  kind === item.id
                    ? 'bg-white text-brand-700 shadow-soft dark:bg-ink-800 dark:text-brand-300'
                    : 'text-ink-500 hover:text-ink-800 dark:text-ink-400 dark:hover:text-ink-100'
                }`}
              >
                {item.icon}
                {item.label}
              </button>
            ))}
          </div>

          <div className="mt-5 min-h-[150px]">
            {kind === 'github' && (
              <Field label="GitHub 仓库地址" hint="支持 owner/repo、https://github.com/owner/repo、git@github.com:owner/repo.git，可追加 #分支">
                <input
                  value={githubText}
                  onChange={(event) => setGithubText(event.target.value)}
                  onKeyDown={(event) => event.key === 'Enter' && !running && void install()}
                  placeholder="deepseek-ai/deepseek-harness"
                  className="input-base"
                />
                {githubPreview && (
                  <div className="mt-2 flex items-center gap-1.5 text-[11px] font-medium text-emerald-600 dark:text-emerald-400">
                    <CheckCircle2 size={12} /> {githubPreview}
                  </div>
                )}
              </Field>
            )}
            {kind === 'npm' && (
              <Field label="npm 包名" hint="等价于 dsh plugin --profile <name> add <package>">
                <input
                  value={npmText}
                  onChange={(event) => setNpmText(event.target.value)}
                  onKeyDown={(event) => event.key === 'Enter' && !running && void install()}
                  placeholder="@scope/plugin-name"
                  className="input-base"
                />
              </Field>
            )}
            {(kind === 'zip' || kind === 'folder') && (
              <Field
                label={kind === 'zip' ? 'ZIP 压缩包' : '本地插件文件夹'}
                hint={
                  kind === 'zip'
                    ? '解压后自动定位 package.json（根目录或唯一顶层文件夹），源码持久保存到应用数据目录 PluginSources。'
                    : '文件夹必须包含 package.json；以 file: 路径安装，不复制源码、节省磁盘。'
                }
              >
                <div className="flex items-center gap-2">
                  <div className="input-base min-w-0 flex-1 truncate text-ink-400">{filePath || '未选择'}</div>
                  <button
                    onClick={() => {
                      const picker = kind === 'zip' ? window.api.plugins.pickZip() : window.api.plugins.pickFolder()
                      void picker.then((path) => path && setFilePath(path))
                    }}
                    className="shrink-0 rounded-lg border border-ink-200 bg-white px-3 py-2 text-[11.5px] font-medium text-ink-600 shadow-soft transition hover:border-brand-300 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300"
                  >
                    选择{kind === 'zip' ? ' .zip…' : '文件夹…'}
                  </button>
                </div>
              </Field>
            )}
          </div>

          {error && (
            <div className="mt-3 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-[11.5px] leading-relaxed text-red-600 dark:border-red-500/20 dark:bg-red-500/10 dark:text-red-400">
              {error}
            </div>
          )}

          <div className="mt-4">
            <div className="mb-1.5 text-[10px] font-semibold uppercase tracking-wider text-ink-400">实时日志</div>
            <div className="h-28 overflow-y-auto rounded-lg bg-ink-950 px-3 py-2 font-mono text-[10.5px] leading-relaxed text-ink-300">
              {logs.length === 0 ? (
                <span className="text-ink-600">等待执行命令…</span>
              ) : (
                logs.map((entry) => (
                  <div key={entry.id} className={entry.level === 'error' || entry.level === 'stderr' ? 'text-red-400' : entry.level === 'success' ? 'text-emerald-400' : ''}>
                    <span className="text-ink-600">{new Date(entry.date).toLocaleTimeString('zh-CN', { hour12: false })} </span>
                    {entry.text}
                  </div>
                ))
              )}
            </div>
          </div>
        </div>

        <div className="flex items-center justify-end gap-2 border-t border-ink-200/70 px-5 py-3.5 dark:border-white/[0.06]">
          <button onClick={onClose} className="rounded-lg border border-ink-200 bg-white px-3.5 py-2 text-[12px] font-medium text-ink-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300">
            取消
          </button>
          <button
            onClick={() => void install()}
            disabled={running}
            className="flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-4 py-2 text-[12px] font-semibold text-white shadow-soft transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
          >
            {running ? <span className="size-3 animate-spin rounded-full border-2 border-white/40 border-t-white" /> : null}
            {running ? '安装中…' : '安装'}
          </button>
        </div>
      </div>
    </div>
  )
}

function Field({ label, hint, children }: { label: string; hint: string; children: React.ReactNode }): React.JSX.Element {
  return (
    <label className="block">
      <span className="text-[12px] font-semibold text-ink-700 dark:text-ink-200">{label}</span>
      <div className="mt-1.5">{children}</div>
      <span className="mt-1.5 block text-[10.5px] leading-relaxed text-ink-400">{hint}</span>
    </label>
  )
}
