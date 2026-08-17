import { Blocks, Palette, Store } from 'lucide-react'

export type PluginSection = 'installed' | 'marketplace' | 'skins'

export default function PluginSectionTabs({
  section,
  onChange
}: {
  section: PluginSection
  onChange: (section: PluginSection) => void
}): React.JSX.Element {
  return (
    <div className="inline-flex items-center gap-0.5 rounded-lg bg-ink-100 p-0.5 dark:bg-white/[0.05]">
      <TabButton active={section === 'installed'} onClick={() => onChange('installed')}>
        <Blocks size={12} /> 已安装
      </TabButton>
      <TabButton active={section === 'marketplace'} onClick={() => onChange('marketplace')}>
        <Store size={12} /> 插件市场
      </TabButton>
      <TabButton active={section === 'skins'} onClick={() => onChange('skins')}>
        <Palette size={12} /> 皮肤中心
      </TabButton>
    </div>
  )
}

function TabButton({
  active,
  onClick,
  children
}: {
  active: boolean
  onClick: () => void
  children: React.ReactNode
}): React.JSX.Element {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-[11px] font-semibold transition ${
        active
          ? 'bg-white text-brand-700 shadow-soft dark:bg-ink-800 dark:text-brand-300'
          : 'text-ink-500 hover:text-ink-800 dark:text-ink-400 dark:hover:text-ink-100'
      }`}
    >
      {children}
    </button>
  )
}
