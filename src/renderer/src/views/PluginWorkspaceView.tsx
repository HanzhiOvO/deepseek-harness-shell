import { useState } from 'react'
import MarketplaceView from './MarketplaceView'
import PluginsView from './PluginsView'
import type { PluginSection } from '../components/PluginSectionTabs'

export default function PluginWorkspaceView(): React.JSX.Element {
  const [section, setSection] = useState<PluginSection>('installed')

  if (section === 'marketplace') {
    return <MarketplaceView kind="plugins" onSectionChange={setSection} />
  }
  if (section === 'skins') {
    return <MarketplaceView kind="skins" onSectionChange={setSection} />
  }
  return <PluginsView onSectionChange={setSection} />
}
