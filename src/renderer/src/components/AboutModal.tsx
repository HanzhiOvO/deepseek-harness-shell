import { Blocks, Cpu, Leaf, TerminalSquare, X } from 'lucide-react'
import { useAppStore } from '../state/store'

export default function AboutModal({ open, onClose }: { open: boolean; onClose: () => void }): React.JSX.Element | null {
  const snapshot = useAppStore()
  if (!open) return null

  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-ink-950/35 p-6 backdrop-blur-sm" onMouseDown={onClose}>
      <div
        className="animate-scale-in w-full max-w-[520px] rounded-2xl border border-ink-200 bg-white p-6 shadow-lifted dark:border-white/10 dark:bg-ink-900"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="flex items-start justify-between">
          <div className="flex items-center gap-3.5">
            <div className="grid size-12 place-items-center rounded-2xl bg-gradient-to-br from-brand-400 to-brand-900 text-white shadow-lifted">
              <TerminalSquare size={20} />
            </div>
            <div>
              <h2 className="text-lg font-semibold tracking-tight">DeepSeek Harness Shell</h2>
              <p className="text-xs text-ink-500 dark:text-ink-400">社区项目 · v{snapshot.appVersion} · 不代表 DeepSeek 官方立场</p>
            </div>
          </div>
          <button onClick={onClose} className="grid size-7 place-items-center rounded-lg text-ink-400 hover:bg-ink-100 dark:hover:bg-white/5">
            <X size={15} />
          </button>
        </div>

        <p className="mt-4 text-[13px] leading-relaxed text-ink-600 dark:text-ink-300">
          把上游 DeepSeek Harness 装进 Windows / macOS / Linux 的轻量桌面体验：自动配置环境、插件中心、会话同步、运行日志与内嵌 dsh Web
          UI。应用不捆绑 dsh / Node.js / pnpm，数据仍保存在你的 DSH_HOME。
        </p>

        <div className="mt-3 rounded-xl border border-amber-300/60 bg-amber-50 px-3.5 py-2.5 text-[11px] leading-relaxed text-amber-700 dark:border-amber-500/20 dark:bg-amber-500/10 dark:text-amber-300">
          本应用是 <b>dsh 社区项目</b>，由社区开发者维护，与 DeepSeek 公司及 DeepSeek Harness
          官方团队无关；不代表官方立场，也不是官方作品。
        </div>

        <div className="mt-4 flex flex-wrap gap-2">
          <FeatureBadge icon={<Leaf size={12} />} text="低能耗" />
          <FeatureBadge icon={<Cpu size={12} />} text="三平台" />
          <FeatureBadge icon={<Blocks size={12} />} text={`dsh ${snapshot.tools.dsh?.version ?? '未安装'}`} />
        </div>

        <div className="mt-5 flex items-center justify-between">
          <div className="flex gap-2 text-[11px]">
            <button
              onClick={() => void window.api.shell.openExternal('https://github.com/deepseek-ai/deepseek-harness')}
              className="rounded-lg px-2 py-1 font-medium text-brand-600 hover:bg-brand-50 dark:text-brand-300 dark:hover:bg-brand-500/10"
            >
              上游 dsh 仓库
            </button>
            <button
              onClick={() => void window.api.shell.openExternal('https://nodejs.org/zh-cn/download')}
              className="rounded-lg px-2 py-1 font-medium text-brand-600 hover:bg-brand-50 dark:text-brand-300 dark:hover:bg-brand-500/10"
            >
              Node.js 下载
            </button>
          </div>
          <button
            onClick={onClose}
            className="rounded-lg bg-gradient-to-br from-brand-400 to-brand-700 px-3.5 py-1.5 text-xs font-semibold text-white shadow-soft hover:brightness-110"
          >
            完成
          </button>
        </div>
      </div>
    </div>
  )
}

function FeatureBadge({ icon, text }: { icon: React.ReactNode; text: string }): React.JSX.Element {
  return (
    <span className="flex items-center gap-1.5 rounded-full bg-ink-100 px-2.5 py-1 text-[11px] font-medium text-ink-600 dark:bg-white/[0.06] dark:text-ink-300">
      {icon}
      {text}
    </span>
  )
}
