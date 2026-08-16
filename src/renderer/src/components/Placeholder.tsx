import { useState } from 'react'
import {
  ArrowDownToDot,
  ArrowRight,
  Blocks,
  Cpu,
  HardDrive,
  Leaf,
  MessageSquare,
  Play,
  RefreshCw,
  Rocket,
  ScrollText,
  TerminalSquare,
  TriangleAlert,
  Wrench
} from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import { relativeTime } from '@shared/parsers'

export default function Placeholder(): React.JSX.Element {
  const snapshot = useAppStore()
  const env = snapshot.envState
  const working = snapshot.envWorking

  return (
    <div className="relative h-full overflow-y-auto">
      <div className="pointer-events-none absolute -left-24 -top-32 size-[420px] rounded-full bg-brand-400/10 blur-[90px]" />
      <div className="pointer-events-none absolute -bottom-24 right-0 size-[380px] rounded-full bg-indigo-400/10 blur-[90px]" />

      <div className="relative mx-auto flex min-h-full max-w-[760px] flex-col items-center px-8 py-12">
        <div className="animate-fade-up flex flex-col items-center text-center">
          <div className="grid size-16 place-items-center rounded-[20px] bg-gradient-to-br from-brand-400 via-brand-600 to-brand-950 text-white shadow-lifted">
            <TerminalSquare size={26} strokeWidth={2} />
          </div>
          <h1 className="mt-5 text-3xl font-bold tracking-tight text-ink-900 dark:text-white">DeepSeek Harness Shell</h1>
          <p className="text-balance mt-2 max-w-[540px] text-[13px] leading-relaxed text-ink-500 dark:text-ink-400">
            自动配置环境、管理插件，并把上游 dsh Web UI 装进一个现代、轻盈、跨平台的桌面应用。
          </p>
          <div className="mt-3 flex items-center gap-2">
            <Badge icon={<Leaf size={11} />} text="低能耗" />
            <Badge icon={<Blocks size={11} />} text="Windows · macOS · Linux" />
            <Badge icon={<Cpu size={11} />} text="零轮询" />
          </div>
        </div>

        <div className="animate-fade-up mt-9 w-full max-w-[600px]" style={{ animationDelay: '60ms' }}>
          <EnvCard envKind={env?.kind ?? 'idle'} detail={env?.detail ?? ''} working={working} />
        </div>

        {env?.kind === 'ready' && snapshot.sessions.length > 0 && (
          <div className="animate-fade-up mt-5 w-full max-w-[600px]" style={{ animationDelay: '110ms' }}>
            <div className="mb-2 flex items-center gap-2 text-[11px] font-semibold uppercase tracking-wider text-ink-400">
              <MessageSquare size={11} /> 继续最近会话
            </div>
            <div className="space-y-1.5">
              {snapshot.sessions.slice(0, 3).map((session) => (
                <button
                  key={session.id}
                  onClick={() => {
                    appStore.setView('chat')
                    void window.api.web.openSession(session.id, session.displayTitle)
                  }}
                  className="group flex w-full items-center gap-3 rounded-xl border border-ink-200 bg-white/70 px-3.5 py-2.5 text-left shadow-soft transition hover:-translate-y-px hover:border-brand-300 hover:shadow-lifted dark:border-white/[0.07] dark:bg-white/[0.04] dark:hover:border-brand-500/40"
                >
                  <span className="grid size-8 place-items-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">
                    <MessageSquare size={13} />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[12.5px] font-semibold text-ink-800 dark:text-ink-100">{session.displayTitle}</span>
                    <span className="block truncate text-[10.5px] text-ink-400">
                      {session.projectName} · {session.workspacePath ?? '未知工作区'} · {relativeTime(session.updatedAt)}
                    </span>
                  </span>
                  <ArrowRight size={13} className="text-ink-300 transition group-hover:translate-x-0.5 group-hover:text-brand-500" />
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="animate-fade-up mt-10 grid w-full max-w-[600px] grid-cols-3 gap-3" style={{ animationDelay: '150ms' }}>
          <FeatureCard icon={<Wrench size={15} />} title="自动环境" text="检测与一键安装 dsh / Node / pnpm" />
          <FeatureCard icon={<Blocks size={15} />} title="插件中心" text="GitHub / ZIP / 文件夹 / npm 安装" />
          <FeatureCard icon={<ScrollText size={15} />} title="实时日志" text="按来源与级别过滤，可导出" />
        </div>

        <div className="mt-8 flex items-center gap-2 text-[10.5px] text-ink-400">
          <kbd className="rounded border border-ink-200 bg-white px-1.5 py-0.5 font-mono dark:border-white/10 dark:bg-white/5">⌘R</kbd> 启动
          <span>·</span>
          <kbd className="rounded border border-ink-200 bg-white px-1.5 py-0.5 font-mono dark:border-white/10 dark:bg-white/5">⌘.</kbd> 停止
          <span>·</span>
          <kbd className="rounded border border-ink-200 bg-white px-1.5 py-0.5 font-mono dark:border-white/10 dark:bg-white/5">⌘K</kbd> 快速跳转
        </div>
      </div>
    </div>
  )
}

function EnvCard({ envKind, detail, working }: { envKind: string; detail: string; working: boolean }): React.JSX.Element {
  const snapshot = useAppStore()
  const [busy, setBusy] = useState(false)

  const config = {
    ready: { icon: <Rocket size={20} />, tint: 'text-emerald-600 dark:text-emerald-400 bg-emerald-500/10', title: '环境已就绪' },
    checking: { icon: <RefreshCw size={20} className="animate-spin" />, tint: 'text-amber-600 dark:text-amber-400 bg-amber-500/10', title: '正在检测运行环境…' },
    idle: { icon: <RefreshCw size={20} className="animate-spin" />, tint: 'text-amber-600 dark:text-amber-400 bg-amber-500/10', title: '正在检测运行环境…' },
    installing: { icon: <ArrowDownToDot size={20} />, tint: 'text-brand-600 dark:text-brand-400 bg-brand-500/10', title: '正在安装…' },
    'missing-dsh': { icon: <TriangleAlert size={20} />, tint: 'text-amber-600 dark:text-amber-400 bg-amber-500/10', title: '尚未安装 dsh' },
    'missing-node': { icon: <TriangleAlert size={20} />, tint: 'text-amber-600 dark:text-amber-400 bg-amber-500/10', title: '缺少 Node.js 运行时' },
    'missing-npm': { icon: <TriangleAlert size={20} />, tint: 'text-amber-600 dark:text-amber-400 bg-amber-500/10', title: 'Node.js 的 npm 不可用' },
    failed: { icon: <TriangleAlert size={20} />, tint: 'text-red-600 dark:text-red-400 bg-red-500/10', title: '环境配置失败' }
  }[envKind] ?? {
    icon: <RefreshCw size={20} className="animate-spin" />,
    tint: 'text-amber-600 dark:text-amber-400 bg-amber-500/10',
    title: '正在检测运行环境…'
  }

  return (
    <div className="rounded-2xl border border-ink-200 bg-white/80 p-5 shadow-soft glass dark:border-white/[0.07] dark:bg-white/[0.04]">
      <div className="flex items-start gap-4">
        <span className={`grid size-11 shrink-0 place-items-center rounded-xl ${config.tint}`}>{config.icon}</span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h3 className="text-[15px] font-semibold text-ink-900 dark:text-white">{config.title}</h3>
            {snapshot.tools.dsh && <span className="rounded-full bg-ink-100 px-2 py-0.5 text-[10px] font-medium text-ink-500 dark:bg-white/[0.06] dark:text-ink-400">dsh {snapshot.tools.dsh.version}</span>}
          </div>
          <p className="mt-1 text-[12px] leading-relaxed text-ink-500 dark:text-ink-400">{detail}</p>
        </div>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-2">
        {envKind === 'ready' && (
          <PrimaryButton
            onClick={() => void window.api.web.start()}
            icon={<Play size={13} fill="currentColor" />}
            text="启动 DeepSeek Harness"
          />
        )}
        {envKind === 'missing-dsh' && (
          <PrimaryButton
            disabled={working || busy}
            onClick={() => {
              setBusy(true)
              void window.api.environment.installDsh().finally(() => setBusy(false))
            }}
            icon={<ArrowDownToDot size={13} />}
            text={working || busy ? '正在安装…' : '一键安装 @deepseek-ai/dsh'}
          />
        )}
        {envKind === 'missing-node' && snapshot.tools.brew && (
          <PrimaryButton
            disabled={working}
            onClick={() => void window.api.environment.installNode()}
            icon={<ArrowDownToDot size={13} />}
            text="通过 Homebrew 安装 Node.js"
          />
        )}
        <GhostButton onClick={() => void window.api.environment.detect()} text="重新检测" icon={<RefreshCw size={12} />} />
        {(envKind === 'missing-node' || envKind === 'missing-npm') && (
          <GhostButton
            onClick={() => void window.api.shell.openExternal('https://nodejs.org/zh-cn/download')}
            text="从 nodejs.org 下载"
            icon={<HardDrive size={12} />}
          />
        )}
        {envKind === 'failed' && (
          <GhostButton onClick={() => appStore.setView('logs')} text="查看日志" icon={<ScrollText size={12} />} />
        )}
      </div>
    </div>
  )
}

function PrimaryButton({
  onClick,
  icon,
  text,
  disabled = false
}: {
  onClick: () => void
  icon: React.ReactNode
  text: string
  disabled?: boolean
}): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className="flex items-center gap-1.5 rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-3.5 py-2 text-[12px] font-semibold text-white shadow-soft transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-60"
    >
      {icon}
      {text}
    </button>
  )
}

function GhostButton({ onClick, text, icon }: { onClick: () => void; text: string; icon: React.ReactNode }): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      className="flex items-center gap-1.5 rounded-lg border border-ink-200 bg-white px-3 py-2 text-[12px] font-medium text-ink-600 shadow-soft transition hover:border-brand-300 hover:text-brand-600 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-300 dark:hover:border-brand-500/40 dark:hover:text-brand-300"
    >
      {icon}
      {text}
    </button>
  )
}

function Badge({ icon, text }: { icon: React.ReactNode; text: string }): React.JSX.Element {
  return (
    <span className="flex items-center gap-1.5 rounded-full border border-ink-200 bg-white/70 px-2.5 py-1 text-[10.5px] font-medium text-ink-500 dark:border-white/10 dark:bg-white/[0.04] dark:text-ink-400">
      {icon}
      {text}
    </span>
  )
}

function FeatureCard({ icon, title, text }: { icon: React.ReactNode; title: string; text: string }): React.JSX.Element {
  return (
    <div className="rounded-xl border border-ink-200 bg-white/70 p-3.5 shadow-soft dark:border-white/[0.07] dark:bg-white/[0.03]">
      <span className="grid size-7 place-items-center rounded-lg bg-brand-50 text-brand-600 dark:bg-brand-500/15 dark:text-brand-300">{icon}</span>
      <div className="mt-2.5 text-[12px] font-semibold text-ink-800 dark:text-ink-100">{title}</div>
      <div className="mt-1 text-[10.5px] leading-relaxed text-ink-400">{text}</div>
    </div>
  )
}
