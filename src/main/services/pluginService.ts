import { app } from 'electron'
import { promises as fs, existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, basename } from 'node:path'
import { pathToFileURL } from 'node:url'
import { randomUUID } from 'node:crypto'
import extract from 'extract-zip'
import { streamCommand } from '../core/processRunner'
import type { LogBus } from '../core/logBus'
import type { SettingsService } from './settingsService'
import type { EnvironmentService } from './environmentService'
import type { InstalledPlugin } from '@shared/types'
import {
  parseGitHubSpec,
  locatePackageRoot,
  pluginExternalUrl,
  pluginLocalSource,
  pluginSourceKind
} from '@shared/parsers'

export class PluginService {
  installed: InstalledPlugin[] = []
  profiles: string[] = ['web']
  profileName = 'web'
  isWorking = false

  constructor(
    private settings: SettingsService,
    private environment: EnvironmentService,
    private logs: LogBus,
    private onInstalled: (plugins: InstalledPlugin[]) => void,
    private onProfiles: (profiles: string[]) => void
  ) {
    this.profileName = settings.get().profileName || 'web'
  }

  get dshHomeDirectory(): string {
    const configured = this.settings.get().dshHome.trim()
    if (configured) return expandTilde(configured)
    const envHome = (process.env.DSH_HOME ?? '').trim()
    if (envHome) return expandTilde(envHome)
    return join(homedir(), '.dsh')
  }

  get profileDirectory(): string {
    return join(this.dshHomeDirectory, 'profiles', this.profileName)
  }

  async refreshProfiles(): Promise<void> {
    const profilesRoot = join(this.dshHomeDirectory, 'profiles')
    const names: string[] = []
    try {
      for (const child of (await fs.readdir(profilesRoot)).sort()) {
        if (existsSync(join(profilesRoot, child, 'package.json'))) names.push(child)
      }
    } catch {
      // profiles 目录尚未创建。
    }
    if (!names.includes('web')) names.unshift('web')
    this.profiles = names
    if (!names.includes(this.profileName)) this.profileName = names[0] ?? 'web'
    this.onProfiles(this.profiles)
    this.loadInstalled()
  }

  loadInstalled(): void {
    const manifestPath = join(this.profileDirectory, 'package.json')
    let manifest: Record<string, unknown> | null = null
    try {
      manifest = JSON.parse(readFileSync(manifestPath, 'utf8')) as Record<string, unknown>
    } catch {
      manifest = null
    }

    if (!manifest) {
      const defaults = ['@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app']
      this.installed = defaults.map((name) => this.describe(name, 'dsh 随附 bundle', true, true))
      this.onInstalled(this.installed)
      return
    }

    const dependencies = (manifest.dependencies ?? {}) as Record<string, string>
    const dshSection = (manifest.dsh ?? {}) as Record<string, unknown>
    const profileSection = (dshSection.profile ?? {}) as Record<string, unknown>
    const bundles = Array.isArray(profileSection.bundles) ? (profileSection.bundles as string[]) : []

    const result: InstalledPlugin[] = []
    const namesInDependencies = new Set<string>()
    for (const name of Object.keys(dependencies).sort()) {
      namesInDependencies.add(name)
      result.push(this.describe(name, dependencies[name], bundles.includes(name), false))
    }
    for (const name of bundles) {
      if (!namesInDependencies.has(name)) {
        result.push(this.describe(name, 'dsh 随附 bundle', true, true))
      }
    }
    result.sort((a, b) => {
      if (a.isInbox !== b.isInbox) return a.isInbox ? 1 : -1
      return a.name.localeCompare(b.name)
    })
    this.installed = result
    this.onInstalled(this.installed)
  }

  setProfile(name: string): void {
    const trimmed = name.trim() || 'web'
    this.profileName = trimmed
    this.settings.update({ profileName: trimmed })
    this.loadInstalled()
  }

  async installFromGitHub(input: string): Promise<void> {
    const spec = parseGitHubSpec(input)
    this.logs.append('plugins', 'info', `解析 GitHub 插件：${spec.displayName}`)
    await this.runPlugin(['add', spec.pnpmArgument], `安装 ${spec.displayName}`)
  }

  async installFromZip(archivePath: string): Promise<void> {
    const staging = join(app.getPath('temp'), `dsh-shell-plugin-${randomUUID()}`)
    await fs.mkdir(staging, { recursive: true })
    try {
      this.logs.append('plugins', 'info', `解压 ZIP：${basename(archivePath)}`)
      await extract(archivePath, { dir: staging })

      const entries = walkFiles(staging)
      this.logs.append('plugins', 'info', `ZIP 内文件：${entries.slice(0, 12).join(', ')}${entries.length > 12 ? '…' : ''}`)
      const root = locatePackageRoot(entries)
      if (root === null) {
        throw new Error('压缩包内没有找到 package.json（需位于根目录或唯一顶层文件夹内）')
      }
      const packageRoot = join(staging, root)
      let packageName = 'plugin-' + randomUUID()
      try {
        const manifest = JSON.parse(readFileSync(join(packageRoot, 'package.json'), 'utf8')) as Record<string, unknown>
        if (typeof manifest.name === 'string' && manifest.name.trim()) {
          packageName = manifest.name.replace(/\//g, '_')
        }
      } catch {
        // 使用随机名。
      }

      const sourcesRoot = join(app.getPath('userData'), 'PluginSources')
      const destination = join(sourcesRoot, packageName)
      await fs.mkdir(sourcesRoot, { recursive: true })
      await fs.rm(destination, { recursive: true, force: true })
      await fs.rename(packageRoot, destination)
      this.logs.append('plugins', 'info', `ZIP 源文件已保存到 ${destination}`)
      await this.installFromFolder(destination, basename(archivePath))
    } finally {
      await fs.rm(staging, { recursive: true, force: true }).catch(() => undefined)
    }
  }

  async installFromFolder(folderPath: string, label?: string): Promise<void> {
    if (!existsSync(join(folderPath, 'package.json'))) {
      throw new Error('所选文件夹中必须包含 package.json')
    }
    const spec = pathToFileURL(folderPath).toString()
    await this.runPlugin(['add', spec], `安装 ${label ?? basename(folderPath)}`)
  }

  async installFromNpm(packageName: string): Promise<void> {
    const spec = packageName.trim()
    if (!spec) throw new Error('请输入 npm 包名')
    await this.runPlugin(['add', spec], `安装 ${spec}`)
  }

  async update(plugin: InstalledPlugin): Promise<void> {
    if (plugin.isInbox) throw new Error('内置 bundle 随 dsh 一起升级，不需要单独更新')
    const args = plugin.sourceKind === 'npm' ? ['update', '--latest', plugin.name] : ['update', plugin.name]
    await this.runPlugin(args, `更新 ${plugin.name}`)
  }

  async remove(plugin: InstalledPlugin): Promise<void> {
    if (plugin.isInbox) throw new Error('内置 bundle 由 dsh 随附，不能从 profile 中移除')
    await this.runPlugin(['remove', plugin.name], `移除 ${plugin.name}`)
  }

  // MARK: - 内部

  private describe(name: string, spec: string, isBundle: boolean, isInbox: boolean): InstalledPlugin {
    return {
      name,
      spec,
      version: this.installedVersion(name),
      isBundle,
      isInbox,
      sourceKind: pluginSourceKind(spec),
      localSource: pluginLocalSource(spec),
      externalUrl: pluginExternalUrl(name, spec)
    }
  }

  private installedVersion(packageName: string): string | null {
    const nodeModules = join(this.profileDirectory, 'node_modules')
    const candidates = [join(nodeModules, packageName, 'package.json')]
    const pnpmStore = join(nodeModules, '.pnpm')
    if (existsSync(pnpmStore)) {
      try {
        for (const child of readdirSync(pnpmStore).sort().reverse()) {
          if (child.startsWith(`${packageName}@`)) {
            candidates.push(join(pnpmStore, child, 'node_modules', packageName, 'package.json'))
          }
        }
      } catch {
        // 忽略。
      }
    }
    const dsh = this.environment.dshExecutable
    if (dsh) {
      let dir = dirname(dsh)
      for (let index = 0; index < 8; index += 1) {
        candidates.push(join(dir, 'node_modules', packageName, 'package.json'))
        const parent = dirname(dir)
        if (parent === dir) break
        dir = parent
      }
    }
    for (const candidate of candidates.slice(0, 12)) {
      try {
        const manifest = JSON.parse(readFileSync(candidate, 'utf8')) as Record<string, unknown>
        if (typeof manifest.version === 'string') return manifest.version
      } catch {
        // 下一个候选。
      }
    }
    return null
  }

  private async runPlugin(args: string[], logPrefix: string): Promise<void> {
    const dsh = this.environment.dshExecutable
    if (!dsh) throw new Error('缺少 dsh，请先在「环境与设置」中配置运行环境')
    if (!(await this.environment.ensurePnpm())) {
      throw new Error('无法安装 pnpm（dsh 插件管理依赖 pnpm），请查看运行日志')
    }

    this.isWorking = true
    try {
      const commandLine = `dsh plugin --profile ${this.profileName} ${args.join(' ')}`
      this.logs.append('plugins', 'command', commandLine)
      this.logs.append('plugins', 'info', `${logPrefix}（通过 pnpm 写入 profile「${this.profileName}」）`)

      const env = { ...this.environment.spawnEnvironment }
      const dshHome = this.settings.get().dshHome.trim()
      if (dshHome) env.DSH_HOME = expandTilde(dshHome)

      const code = await new Promise<number | null>((done) => {
        const handle = streamCommand(
          dsh,
          ['plugin', '--profile', this.profileName, ...args],
          {
            onLine: (line, stderr) => this.logs.append('plugins', stderr ? 'stderr' : 'stdout', line),
            onExit: (exitCode, error) => {
              if (error) this.logs.append('plugins', 'error', error)
              done(exitCode)
            }
          },
          { env }
        )
        void handle
      })

      if (code !== 0) {
        throw new Error(`命令失败（exit ${code ?? '?'}），请查看运行日志`)
      }
      this.logs.append('plugins', 'success', `${logPrefix} 完成`)
      this.loadInstalled()
    } finally {
      this.isWorking = false
    }
  }
}

function expandTilde(path: string): string {
  if (path === '~') return homedir()
  if (path.startsWith('~/') || path.startsWith('~\\')) return join(homedir(), path.slice(2))
  return path
}

function walkFiles(root: string): string[] {
  const prefix = root.endsWith('/') ? root : root + '/'
  const result: string[] = []
  const visit = (dir: string): void => {
    let children: string[] = []
    try {
      children = readdirSync(dir)
    } catch {
      return
    }
    for (const child of children) {
      if (child === '__MACOSX' || child.startsWith('.')) continue
      const full = join(dir, child)
      try {
        if (statSync(full).isDirectory()) visit(full)
        else result.push(full.slice(prefix.length))
      } catch {
        // 跳过。
      }
    }
  }
  visit(root)
  return result
}
