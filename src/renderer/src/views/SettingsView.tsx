import { useState } from 'react'
import {
  ArrowDownToDot,
  Eye,
  EyeOff,
  FolderOpen,
  HardDrive,
  KeyRound,
  Monitor,
  Moon,
  RefreshCw,
  RotateCcw,
  ShieldCheck,
  Sun,
  TerminalSquare,
  Wrench
} from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import type { AppearanceMode } from '@shared/types'

export default function SettingsView(): React.JSX.Element {
  const snapshot = useAppStore()
  const settings = snapshot.settings
  const [showKey, setShowKey] = useState(false)
  const [confirmReset, setConfirmReset] = useState(false)
  if (!settings) return <div className="p-8 text-sm text-ink-400">正在读取设置…</div>

  const update = (patch: Parameters<typeof window.api.settings.update>[0]): void => {
    void window.api.settings.update(patch).then(() => appStore.toast('设置已保存', 'success'))
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="mx-auto max-w-[820px] p-6">
        <header className="mb-5 flex items-center gap-3">
          <div className="grid size-10 place-items-center rounded-xl bg-gradient-to-br from-brand-400 to-brand-800 text-white shadow-soft">
            <Wrench size={17} />
          </div>
          <div>
            <h1 className="text-[17px] font-bold tracking-tight text-ink-900 dark:text-white">环境与设置</h1>
            <p className="mt-0.5 text-[11px] text-ink-400">DeepSeek Harness Shell · 跨平台桌面壳</p>
          </div>
        </header>

        <div className="space-y-4">
          <Section title="外观" icon={<Monitor size={14} />}>
            <div className="grid max-w-[400px] grid-cols-3 gap-1 rounded-xl bg-ink-100 p-1 dark:bg-white/[0.05]">
              {(
                [
                  { id: 'system', label: '跟随系统', icon: <Monitor size={13} /> },
                  { id: 'light', label: '浅色', icon: <Sun size={13} /> },
                  { id: 'dark', label: '深色', icon: <Moon size={13} /> }
                ] as { id: AppearanceMode; label: string; icon: React.ReactNode }[]
              ).map((item) => (
                <button
                  key={item.id}
                  onClick={() => update({ appearance: item.id })}
                  className={`flex items-center justify-center gap-1.5 rounded-lg px-2 py-2 text-[11.5px] font-semibold transition ${
                    settings.appearance === item.id
                      ? 'bg-white text-brand-700 shadow-soft dark:bg-ink-800 dark:text-brand-300'
                      : 'text-ink-500 hover:text-ink-800 dark:text-ink-400 dark:hover:text-ink-100'
                  }`}
                >
                  {item.icon}
                  {item.label}
                </button>
              ))}
            </div>
          </Section>

          <Section title="DeepSeek Harness 内核" icon={<TerminalSquare size={14} />}>
            <div className="flex flex-wrap items-center gap-2">
              <EnvPill />
              <ActionButton onClick={() => void window.api.environment.detect()} icon={<RefreshCw size={12} />} text="重新检测" />
              {snapshot.envState?.kind === 'missing-dsh' && snapshot.envState.canInstall && (
                <ActionButton primary onClick={() => void window.api.environment.installDsh()} icon={<ArrowDownToDot size={12} />} text="一键安装 @deepseek-ai/dsh" />
              )}
              {snapshot.envState?.kind === 'missing-node' && snapshot.envState.canInstall && (
                <ActionButton primary onClick={() => void window.api.environment.installNode()} icon={<ArrowDownToDot size={12} />} text="通过 Homebrew 安装 Node.js" />
              )}
              {snapshot.tools.dsh && snapshot.tools.npm && (
                <ActionButton
                  onClick={() => void window.api.environment.updateDsh()}
                  icon={<ArrowDownToDot size={12} />}
                  text="升级 dsh 到最新版"
                  title={snapshot.webState.kind === 'running' ? '升级前请先停止服务' : 'npm install -g @deepseek-ai/dsh@latest'}
                />
              )}
            </div>
            <div className="mt-3">
              <Label>自定义 dsh 路径（留空自动探测）</Label>
              <input value={settings.customDshPath} onChange={(event) => update({ customDshPath: event.target.value })} placeholder="/usr/local/bin/dsh" className="input-base" />
            </div>
          </Section>

          <Section title="启动与运行" icon={<HardDrive size={14} />}>
            <ToggleRow label="启动应用时自动连接 Web UI" checked={settings.autoStartWeb} onChange={(value) => update({ autoStartWeb: value })} />
            <ToggleRow label="检测到缺少 dsh 时自动安装" checked={settings.autoInstallDsh} onChange={(value) => update({ autoInstallDsh: value })} />
            <ToggleRow label="关闭窗口时停止服务并退出" checked={settings.stopWhenClosed} onChange={(value) => update({ stopWhenClosed: value })} hint="关闭时保留到菜单栏/托盘，可降低停止后再启动的等待" />
            <ToggleRow label="关闭 dsh 遥测" checked={settings.telemetryDisabled} onChange={(value) => update({ telemetryDisabled: value })} />
            <div className="mt-3 grid gap-3 sm:grid-cols-3">
              <div>
                <Label>Web 端口（0 = 自动）</Label>
                <input
                  type="number"
                  value={settings.webPort}
                  min={0}
                  max={65535}
                  onChange={(event) => update({ webPort: Number(event.target.value) })}
                  className="input-base"
                />
              </div>
              <div>
                <Label>默认 profile</Label>
                <input value={settings.profileName} onChange={(event) => update({ profileName: event.target.value })} className="input-base" />
              </div>
              <div>
                <Label>DSH_HOME</Label>
                <input value={settings.dshHome} onChange={(event) => update({ dshHome: event.target.value })} placeholder="默认 ~/.dsh" className="input-base" />
              </div>
            </div>
          </Section>

          <Section title="DeepSeek API Key" icon={<KeyRound size={14} />}>
            <div className="relative max-w-[460px]">
              <input
                type={showKey ? 'text' : 'password'}
                value={settings.apiKey}
                onChange={(event) => update({ apiKey: event.target.value })}
                placeholder="sk-…（可选，也可在 Web UI 内登录）"
                className="input-base pr-9"
              />
              <button
                onClick={() => setShowKey(!showKey)}
                className="absolute right-2 top-1/2 grid size-6 -translate-y-1/2 place-items-center rounded text-ink-400 hover:bg-ink-100 dark:hover:bg-white/5"
              >
                {showKey ? <EyeOff size={13} /> : <Eye size={13} />}
              </button>
            </div>
            <p className="mt-1.5 flex items-center gap-1.5 text-[10.5px] text-ink-400">
              <ShieldCheck size={11} className="text-emerald-500" />
              仅作为 DEEPSEEK_API_KEY 传给 dsh 子进程，设置文件以 0600 权限保存。
            </p>
          </Section>

          <Section title="工具链" icon={<Wrench size={14} />}>
            {snapshot.tools.dsh || snapshot.tools.node ? (
              <div className="space-y-1">
                {([snapshot.tools.dsh, snapshot.tools.node, snapshot.tools.npm, snapshot.tools.pnpm, snapshot.tools.git, snapshot.tools.brew].filter(Boolean) as { name: string; path: string; version: string | null }[]).map((tool) => (
                  <div key={tool.name} className="flex items-center gap-3 rounded-lg px-2 py-1.5 text-[11px] hover:bg-ink-50 dark:hover:bg-white/[0.03]">
                    <span className="w-10 shrink-0 font-mono font-semibold text-ink-700 dark:text-ink-200">{tool.name}</span>
                    <span className="min-w-0 flex-1 truncate font-mono text-ink-400" title={tool.path}>{tool.path}</span>
                    <span className="shrink-0 rounded bg-ink-100 px-1.5 py-0.5 font-mono text-[10px] text-ink-500 dark:bg-white/[0.06] dark:text-ink-400">{tool.version ?? '?'}</span>
                    <button onClick={() => void window.api.shell.reveal(tool.path)} className="grid size-6 place-items-center rounded text-ink-400 hover:bg-ink-100 dark:hover:bg-white/5" title="在 Finder 中显示">
                      <FolderOpen size={12} />
                    </button>
                  </div>
                ))}
                {!snapshot.tools.pnpm && (
                  <div className="flex items-center justify-between gap-2 rounded-lg bg-amber-50 px-3 py-2 text-[11px] text-amber-700 dark:bg-amber-500/10 dark:text-amber-300">
                    未找到 pnpm，安装插件前会自动准备
                    <button onClick={() => void window.api.environment.ensurePnpm()} className="font-semibold underline-offset-2 hover:underline">现在安装</button>
                  </div>
                )}
              </div>
            ) : (
              <div className="text-[12px] text-ink-400">尚未检测到工具链</div>
            )}
          </Section>

          <Section title="数据与重置" icon={<RotateCcw size={14} />}>
            <div className="flex flex-wrap items-center gap-2">
              <ActionButton onClick={() => void window.api.shell.openPath(snapshot.dataDirs.dshHome)} icon={<HardDrive size={12} />} text="打开 DSH 数据目录" />
              <ActionButton onClick={() => void window.api.shell.openPath(snapshot.dataDirs.profileDirectory)} icon={<FolderOpen size={12} />} text="打开 profile 目录" />
              <ActionButton onClick={() => void window.api.shell.openPath(snapshot.dataDirs.pluginSourcesDirectory)} icon={<FolderOpen size={12} />} text="插件源码目录" />
              <ActionButton onClick={() => appStore.setView('logs')} icon={<TerminalSquare size={12} />} text="查看运行日志" />
              <ActionButton danger onClick={() => setConfirmReset(true)} icon={<RotateCcw size={12} />} text="重置全部设置…" />
            </div>
            <p className="mt-2 text-[10.5px] text-ink-400">应用本身不捆绑 Node / dsh / pnpm / Chromium 之外的运行时，插件与会话数据保存在你的 DSH_HOME。</p>
          </Section>
        </div>
      </div>

      {confirmReset && (
        <div className="fixed inset-0 z-40 grid place-items-center bg-ink-950/35 p-6 backdrop-blur-sm" onMouseDown={() => setConfirmReset(false)}>
          <div className="animate-scale-in w-full max-w-[420px] rounded-2xl border border-ink-200 bg-white p-5 shadow-lifted dark:border-white/10 dark:bg-ink-900" onMouseDown={(event) => event.stopPropagation()}>
            <h3 className="text-[15px] font-semibold text-ink-900 dark:text-white">重置全部设置？</h3>
            <p className="mt-2 text-[12px] leading-relaxed text-ink-500 dark:text-ink-400">清除 API Key、端口、profile、DSH_HOME 与收藏等所有偏好；会话与插件数据不会被删除。</p>
            <div className="mt-5 flex justify-end gap-2">
              <button onClick={() => setConfirmReset(false)} className="rounded-lg border border-ink-200 px-3.5 py-1.5 text-[12px] font-medium text-ink-600 dark:border-white/10 dark:text-ink-300">取消</button>
              <button
                onClick={() => {
                  setConfirmReset(false)
                  void window.api.settings.reset().then(() => appStore.toast('已恢复默认设置', 'success'))
                }}
                className="rounded-lg bg-red-500 px-3.5 py-1.5 text-[12px] font-semibold text-white hover:bg-red-600"
              >
                恢复默认
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}

function EnvPill(): React.JSX.Element {
  const snapshot = useAppStore()
  const kind = snapshot.envState?.kind
  const color = kind === 'ready' ? 'bg-emerald-500' : kind === 'checking' || kind === 'installing' || kind === 'idle' ? 'bg-amber-500 animate-soft-pulse' : kind === 'failed' || kind?.startsWith('missing') ? 'bg-red-500' : 'bg-ink-300'
  return (
    <span className="flex items-center gap-2 rounded-full border border-ink-200 bg-white px-3 py-1.5 text-[11.5px] font-semibold text-ink-700 shadow-soft dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-200">
      <span className={`size-1.5 rounded-full ${color}`} />
      {snapshot.envState?.label ?? '等待检测'}
      {snapshot.tools.dsh && <span className="font-normal text-ink-400">· dsh {snapshot.tools.dsh.version}</span>}
    </span>
  )
}

function Section({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }): React.JSX.Element {
  return (
    <section className="rounded-2xl border border-ink-200 bg-white/75 p-5 shadow-soft dark:border-white/[0.07] dark:bg-white/[0.03]">
      <h2 className="mb-3.5 flex items-center gap-2 text-[13px] font-bold text-ink-800 dark:text-ink-100">
        <span className="grid size-6 place-items-center rounded-md bg-brand-50 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">{icon}</span>
        {title}
      </h2>
      {children}
    </section>
  )
}

function ToggleRow({ label, checked, onChange, hint }: { label: string; checked: boolean; onChange: (value: boolean) => void; hint?: string }): React.JSX.Element {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-ink-100 py-2 last:border-0 dark:border-white/[0.04]">
      <div>
        <div className="text-[12px] font-medium text-ink-700 dark:text-ink-200">{label}</div>
        {hint && <div className="text-[10px] text-ink-400">{hint}</div>}
      </div>
      <button
        onClick={() => onChange(!checked)}
        className={`relative h-5 w-9 shrink-0 rounded-full transition ${checked ? 'bg-brand-500' : 'bg-ink-200 dark:bg-white/10'}`}
        role="switch"
        aria-checked={checked}
      >
        <span className={`absolute top-0.5 size-4 rounded-full bg-white shadow transition-all ${checked ? 'left-[18px]' : 'left-0.5'}`} />
      </button>
    </div>
  )
}

function ActionButton({
  onClick,
  icon,
  text,
  primary = false,
  danger = false,
  title
}: {
  onClick: () => void
  icon: React.ReactNode
  text: string
  primary?: boolean
  danger?: boolean
  title?: string
}): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      title={title}
      className={`flex items-center gap-1.5 rounded-lg px-3 py-1.5 text-[11.5px] font-medium shadow-soft transition ${
        primary
          ? 'bg-gradient-to-br from-brand-400 to-brand-700 font-semibold text-white hover:brightness-110'
          : danger
            ? 'border border-red-200 bg-white text-red-600 hover:bg-red-50 dark:border-red-500/20 dark:bg-white/[0.04] dark:text-red-400'
            : 'border border-ink-200 bg-white text-ink-600 hover:border-brand-300 hover:text-brand-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300 dark:hover:text-brand-300'
      }`}
    >
      {icon}
      {text}
    </button>
  )
}

function Label({ children }: { children: React.ReactNode }): React.JSX.Element {
  return <div className="mb-1.5 text-[11px] font-medium text-ink-500 dark:text-ink-400">{children}</div>
}
