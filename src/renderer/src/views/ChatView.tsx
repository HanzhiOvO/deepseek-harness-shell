import { useEffect, useRef } from 'react'
import {
  ArrowUpRight,
  ChevronLeft,
  ChevronRight,
  Copy,
  ExternalLink,
  Minus,
  Plus,
  RotateCcw
} from 'lucide-react'
import { appStore, useAppStore } from '../state/store'
import Placeholder from '../components/Placeholder'

export default function ChatView(): React.JSX.Element {
  const snapshot = useAppStore()
  const hostRef = useRef<HTMLDivElement>(null)
  const running = snapshot.webState.kind === 'running'

  useEffect(() => {
    if (!running) return
    const updateBounds = (): void => {
      const element = hostRef.current
      if (!element) return
      const rect = element.getBoundingClientRect()
      void window.api.web.setBounds({ x: rect.x, y: rect.y, width: rect.width, height: rect.height })
    }
    updateBounds()
    const observer = new ResizeObserver(updateBounds)
    if (hostRef.current) observer.observe(hostRef.current)
    window.addEventListener('resize', updateBounds)
    return () => {
      observer.disconnect()
      window.removeEventListener('resize', updateBounds)
    }
  }, [running])

  if (!running) return <Placeholder />

  return (
    <div className="flex h-full flex-col">
      <HarnessToolbar />
      <div
        ref={hostRef}
        className="relative min-h-0 flex-1 overflow-hidden bg-[#f4f6fb] dark:bg-[#0d1322]"
        style={{ backgroundImage: 'radial-gradient(circle at 50% 0%, rgba(59,99,240,0.06), transparent 55%)' }}
      />
    </div>
  )
}

function HarnessToolbar(): React.JSX.Element {
  const snapshot = useAppStore()
  const navigation = snapshot.webNavigation
  const url = snapshot.webState.kind === 'running' ? snapshot.webState.url : ''

  return (
    <div className="app-drag flex h-10 shrink-0 items-center gap-1 border-b border-ink-200/70 bg-white/70 px-2.5 dark:border-white/[0.06] dark:bg-ink-900/60">
      <ToolButton disabled={!navigation.canGoBack} onClick={() => void window.api.web.back()} title="后退">
        <ChevronLeft size={14} />
      </ToolButton>
      <ToolButton disabled={!navigation.canGoForward} onClick={() => void window.api.web.forward()} title="前进">
        <ChevronRight size={14} />
      </ToolButton>
      <ToolButton onClick={() => void window.api.web.reload()} title="刷新">
        <RotateCcw size={13} />
      </ToolButton>

      <div className="mx-1 h-4 w-px bg-ink-200 dark:bg-white/10" />

      <ToolButton onClick={() => void window.api.web.zoomOut()} title="缩小 (⌘−)">
        <Minus size={13} />
      </ToolButton>
      <button
        onClick={() => void window.api.web.zoomReset()}
        className="app-no-drag min-w-[44px] rounded-md px-1.5 py-1 text-center font-mono text-[10.5px] font-semibold text-ink-500 transition hover:bg-ink-100 dark:text-ink-400 dark:hover:bg-white/5"
        title="实际大小 (⌘0)"
      >
        {Math.round(navigation.zoomFactor * 100)}%
      </button>
      <ToolButton onClick={() => void window.api.web.zoomIn()} title="放大 (⌘+)">
        <Plus size={13} />
      </ToolButton>

      <div className="mx-1 h-4 w-px bg-ink-200 dark:bg-white/10" />

      <div className="app-no-drag flex min-w-0 flex-1 items-center gap-2 px-1">
        <span className="size-1.5 shrink-0 rounded-full bg-emerald-500" />
        <span className="truncate text-[11px] font-medium text-ink-600 dark:text-ink-300">{navigation.title}</span>
        <span className="truncate font-mono text-[10.5px] text-ink-400">{url.replace(/^https?:\/\//, '')}</span>
      </div>

      <ToolButton
        onClick={() => {
          void navigator.clipboard.writeText(url)
          appStore.toast('服务地址已复制', 'success')
        }}
        title="复制服务地址"
      >
        <Copy size={13} />
      </ToolButton>
      <ToolButton onClick={() => void window.api.web.openExternal()} title="在系统浏览器打开">
        <ExternalLink size={13} />
      </ToolButton>
      <ToolButton onClick={() => void window.api.shell.openExternal('https://github.com/deepseek-ai/deepseek-harness')} title="官方仓库">
        <ArrowUpRight size={13} />
      </ToolButton>
    </div>
  )
}

function ToolButton({
  children,
  onClick,
  disabled = false,
  title
}: {
  children: React.ReactNode
  onClick: () => void
  disabled?: boolean
  title: string
}): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      title={title}
      className="app-no-drag grid size-6.5 place-items-center rounded-md text-ink-500 transition hover:bg-ink-100 hover:text-ink-900 disabled:cursor-not-allowed disabled:opacity-30 dark:text-ink-400 dark:hover:bg-white/5 dark:hover:text-ink-50"
    >
      {children}
    </button>
  )
}
