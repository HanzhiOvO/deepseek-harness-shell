import { app } from 'electron'
import { promises as fs } from 'node:fs'
import { dirname } from 'node:path'
import type { AppSettingsData } from '@shared/types'
import { sanitizePort } from '@shared/parsers'

export const DEFAULT_SETTINGS: AppSettingsData = {
  autoStartWeb: true,
  autoInstallDsh: true,
  stopWhenClosed: true,
  telemetryDisabled: true,
  webPort: 0,
  profileName: 'web',
  apiKey: '',
  customDshPath: '',
  dshHome: '',
  appearance: 'system',
  pinnedSessionIds: []
}

export class SettingsService {
  private data: AppSettingsData = { ...DEFAULT_SETTINGS }
  private filePath: string
  private loaded = false

  constructor(private onChanged: (settings: AppSettingsData) => void) {
    this.filePath = `${app.getPath('userData')}/settings.json`
  }

  async load(): Promise<void> {
    try {
      const raw = await fs.readFile(this.filePath, 'utf8')
      const parsed = JSON.parse(raw) as Partial<AppSettingsData>
      this.data = {
        ...DEFAULT_SETTINGS,
        ...parsed,
        webPort: sanitizePort(Number(parsed.webPort ?? 0)),
        profileName: (parsed.profileName ?? 'web').trim() || 'web',
        appearance: ['system', 'light', 'dark'].includes(parsed.appearance ?? 'system')
          ? (parsed.appearance as AppSettingsData['appearance'])
          : 'system',
        pinnedSessionIds: Array.isArray(parsed.pinnedSessionIds) ? parsed.pinnedSessionIds : []
      }
    } catch {
      this.data = { ...DEFAULT_SETTINGS }
    }
    this.loaded = true
    await this.persist()
    this.onChanged(this.get())
  }

  get(): AppSettingsData {
    return structuredClone(this.data)
  }

  update(patch: Partial<AppSettingsData>): AppSettingsData {
    this.data = {
      ...this.data,
      ...patch,
      webPort: sanitizePort(Number(patch.webPort ?? this.data.webPort))
    }
    void this.persist()
    this.onChanged(this.get())
    return this.get()
  }

  reset(): AppSettingsData {
    this.data = { ...DEFAULT_SETTINGS }
    void this.persist()
    this.onChanged(this.get())
    return this.get()
  }

  isPinned(sessionId: string): boolean {
    return this.data.pinnedSessionIds.includes(sessionId)
  }

  togglePin(sessionId: string): boolean {
    const index = this.data.pinnedSessionIds.indexOf(sessionId)
    if (index >= 0) this.data.pinnedSessionIds.splice(index, 1)
    else this.data.pinnedSessionIds.push(sessionId)
    void this.persist()
    this.onChanged(this.get())
    return index < 0
  }

  private async persist(): Promise<void> {
    if (!this.loaded) return
    try {
      await fs.mkdir(dirname(this.filePath), { recursive: true })
      const file = `${this.filePath}.tmp`
      await fs.writeFile(file, JSON.stringify(this.data, null, 2), 'utf8')
      await fs.rename(file, this.filePath)
      await fs.chmod(this.filePath, 0o600)
    } catch (error) {
      console.error('[settings] persist failed:', error)
    }
  }
}
