import { useState } from 'react'
import { ArrowUpRight, Copy, ExternalLink, Maximize2, RotateCcw } from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import Placeholder from '../components/Placeholder'

export default function ChatView(): React.JSX.Element {
  const snapshot = useAppStore()
  const running = snapshot.webState.kind === 'running'
  const url = snapshot.webState.kind === 'running' ? snapshot.webState.url : ''
  const [frameKey, setFrameKey] = useState(0)

  if (!running) return <Placeholder />

  return (
    <div className="flex h-full flex-col">
      <div className="app-drag flex h-10 shrink-0 items-center gap-1 border-b border-ink-200/70 bg-white/70 px-2.5 dark:border-white/[0.06] dark:bg-ink-900/60">
        <ToolButton
          title="刷新官方界面"
          onClick={() => {
            setFrameKey((key) => key + 1)
            appStore.toast('Web UI 已刷新', 'success')
          }}
        >
          <RotateCcw size={13} />
        </ToolButton>
        <ToolButton title="在独立窗口打开" onClick={() => void window.api.web.openWindow()}>
          <Maximize2 size={13} />
        </ToolButton>

        <div className="mx-1 h-4 w-px bg-ink-200 dark:bg-white/10" />

        <div className="app-no-drag flex min-w-0 flex-1 items-center gap-2 px-1">
          <span className="size-1.5 shrink-0 rounded-full bg-emerald-500" />
          <span className="truncate text-[11px] font-medium text-ink-600 dark:text-ink-300">官方 DeepSeek Harness Web UI</span>
          <span className="truncate font-mono text-[10.5px] text-ink-400">{url.replace(/^https?:\/\//, '')}</span>
        </div>

        <ToolButton
          title="复制服务地址"
          onClick={() => {
            void navigator.clipboard.writeText(url)
            appStore.toast('服务地址已复制', 'success')
          }}
        >
          <Copy size={13} />
        </ToolButton>
        <ToolButton title="在系统浏览器打开" onClick={() => void window.api.web.openExternal()}>
          <ExternalLink size={13} />
        </ToolButton>
        <ToolButton title="官方仓库" onClick={() => void window.api.shell.openExternal('https://github.com/deepseek-ai/deepseek-harness')}>
          <ArrowUpRight size={13} />
        </ToolButton>
      </div>

      <div className="min-h-0 flex-1 bg-white dark:bg-[#0d1322]">
        <iframe
          key={frameKey}
          src={url}
          title="DeepSeek Harness"
          className="h-full w-full border-0"
          sandbox="allow-forms allow-modals allow-pointer-lock allow-popups allow-same-origin allow-scripts allow-top-navigation-by-user-activation"
        />
      </div>
    </div>
  )
}

function ToolButton({
  children,
  onClick,
  title
}: {
  children: React.ReactNode
  onClick: () => void
  title: string
}): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      title={title}
      className="app-no-drag grid size-7 place-items-center rounded-md text-ink-500 transition hover:bg-ink-100 hover:text-ink-900 dark:text-ink-400 dark:hover:bg-white/5 dark:hover:text-ink-50"
    >
      {children}
    </button>
  )
}
