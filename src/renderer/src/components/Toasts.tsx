import { CheckCircle2, Info, XCircle } from 'lucide-react'
import { useAppStore } from '../state/store'

export default function Toasts(): React.JSX.Element | null {
  const snapshot = useAppStore()
  if (snapshot.toasts.length === 0) return null
  return (
    <div className="pointer-events-none fixed inset-x-0 bottom-5 z-50 flex flex-col items-center gap-2">
      {snapshot.toasts.map((toast) => {
        const Icon = toast.kind === 'success' ? CheckCircle2 : toast.kind === 'error' ? XCircle : Info
        const color =
          toast.kind === 'success' ? 'text-emerald-500' : toast.kind === 'error' ? 'text-red-500' : 'text-brand-500'
        return (
          <div
            key={toast.id}
            className="animate-fade-up pointer-events-auto flex max-w-[560px] items-center gap-2.5 rounded-xl border border-ink-200 bg-white/90 px-3.5 py-2.5 text-[12px] font-medium text-ink-800 shadow-lifted glass dark:border-white/10 dark:bg-ink-800/90 dark:text-ink-100"
          >
            <Icon size={15} className={color} />
            <span className="leading-snug">{toast.message}</span>
          </div>
        )
      })}
    </div>
  )
}
