import { app } from 'electron'
import { promises as fs } from 'node:fs'
import { constants as fsConstants, existsSync, readdirSync } from 'node:fs'
import { homedir } from 'node:os'
import { delimiter, dirname, join, resolve } from 'node:path'
import { runCommand, streamCommand } from '../core/processRunner'
import type { LogBus } from '../core/logBus'
import type { SettingsService } from './settingsService'
import type { EnvironmentState, Toolchain, ToolInfo } from '@shared/types'

const WINDOWS = process.platform === 'win32'

function executableCandidates(name: string, directories: string[]): string[] {
  const extensions = WINDOWS
    ? ['.exe', '.cmd', '.bat', '']
    : ['']
  const seen = new Set<string>()
  const result: string[] = []
  for (const dir of directories) {
    for (const extension of extensions) {
      const path = resolve(dir, name + extension)
      if (!seen.has(path)) {
        seen.add(path)
        result.push(path)
      }
    }
  }
  return result
}

function candidateDirectories(): string[] {
  const home = homedir()
  const dirs: string[] = []
  const push = (...paths: string[]): void => {
    for (const path of paths) {
      const normalized = resolve(path)
      if (!dirs.includes(normalized)) dirs.push(normalized)
    }
  }

  if (process.env.PATH) {
    for (const entry of process.env.PATH.split(delimiter)) {
      if (entry) push(entry)
    }
  }

  push(
    join(home, '.local', 'bin'),
    join(home, '.npm-global', 'bin'),
    join(home, 'Library', 'pnpm'),
    '/opt/homebrew/bin',
    '/opt/homebrew/opt/node/bin',
    '/opt/homebrew/opt/corepack/bin',
    '/opt/homebrew/opt/pnpm/bin',
    '/usr/local/bin',
    '/usr/local/opt/node/bin',
    '/usr/local/opt/corepack/bin',
    '/usr/local/opt/pnpm/bin',
    '/opt/local/bin',
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    join(home, '.volta', 'bin'),
    join(home, '.asdf', 'shims'),
    join(home, '.mise', 'shims'),
    join(home, '.local', 'share', 'mise', 'shims'),
    join(home, 'miniconda3', 'bin'),
    join(home, 'anaconda3', 'bin'),
    join(home, 'miniforge3', 'bin'),
    join(home, 'micromamba', 'bin'),
    join(home, 'AppData', 'Roaming', 'npm'),
    join(home, 'AppData', 'Local', 'Volta', 'bin'),
    'C:\\Program Files\\nodejs',
    'C:\\Program Files (x86)\\nodejs'
  )

  // Homebrew 版本化公式。
  for (const optRoot of ['/opt/homebrew/opt', '/usr/local/opt']) {
    try {
      // 同步列目录只在探测阶段发生一次，成本可接受。
      for (const child of readdirSync(optRoot)) {
        if (child.startsWith('node') || child === 'corepack' || child === 'pnpm') {
          push(join(optRoot, child, 'bin'))
        }
      }
    } catch {
      // 目录不存在。
    }
  }

  return dirs
}

export class EnvironmentService {
  state: EnvironmentState = { kind: 'idle', label: '等待检测', canInstall: false, detail: '' }
  tools: Toolchain = {
    dsh: null,
    node: null,
    npm: null,
    pnpm: null,
    git: null,
    brew: null,
    knownBinDirectories: []
  }
  spawnEnvironment: NodeJS.ProcessEnv = { ...process.env }
  isWorking = false

  private extraDirectories = candidateDirectories()

  constructor(
    private settings: SettingsService,
    private logs: LogBus,
    private onState: (state: EnvironmentState) => void,
    private onTools: (tools: Toolchain) => void
  ) {}

  get dshExecutable(): string | null {
    return this.tools.dsh?.path ?? null
  }

  get npmExecutable(): string | null {
    return this.tools.npm?.path ?? null
  }

  get pnpmExecutable(): string | null {
    return this.tools.pnpm?.path ?? null
  }

  async detect(): Promise<void> {
    if (this.isWorking) return
    this.isWorking = true
    this.setState({ kind: 'checking', label: '正在检测环境…', canInstall: false, detail: '' })
    this.logs.append('environment', 'info', '开始检测 DeepSeek Harness 运行环境')

    const tools = await this.probe()
    this.tools = tools
    this.spawnEnvironment = this.buildEnvironment(tools.knownBinDirectories)
    this.applySettingsOverrides()
    this.onTools(this.tools)

    const summary = [tools.dsh, tools.node, tools.npm, tools.pnpm, tools.git, tools.brew]
      .filter((tool): tool is ToolInfo => Boolean(tool))
      .map((tool) => `${tool.name} ${tool.version ?? '?'}`)
      .join(', ')
    this.logs.append('environment', 'info', summary ? `检测到工具链：${summary}` : '未检测到任何工具链')

    if (tools.dsh) {
      this.setState({ kind: 'ready', label: '环境就绪', canInstall: false, detail: `dsh ${tools.dsh.version ?? ''}` })
      this.logs.append('environment', 'success', `dsh 可用：${tools.dsh.version ?? '?'}`)
    } else if (tools.node && tools.npm) {
      this.setState({
        kind: 'missing-dsh',
        label: '缺少 dsh',
        canInstall: true,
        detail: '检测到 Node.js 与 npm，可自动安装 @deepseek-ai/dsh'
      })
      this.logs.append('environment', 'warning', '未找到 dsh；可通过 npm 用户级前缀安装')
    } else if (tools.node) {
      this.setState({
        kind: 'missing-npm',
        label: '缺少 npm',
        canInstall: false,
        detail: `检测到 Node.js v${tools.node.version ?? '?'}，但 npm 不可用，请确认安装完整`
      })
    } else if (tools.brew) {
      this.setState({
        kind: 'missing-node',
        label: '缺少 Node.js',
        canInstall: true,
        detail: '检测到 Homebrew，可自动安装 Node.js（需要几分钟）'
      })
    } else {
      this.setState({
        kind: 'missing-node',
        label: '缺少 Node.js',
        canInstall: false,
        detail: '未找到 Node.js，请从 https://nodejs.org 安装 Node.js 22.19+ 或 24+'
      })
    }
    this.isWorking = false
  }

  refreshOverrides(): void {
    this.applySettingsOverrides()
  }

  async installDsh(): Promise<boolean> {
    return this.installOrUpdateDsh('安装', '@deepseek-ai/dsh')
  }

  async updateDsh(): Promise<boolean> {
    return this.installOrUpdateDsh('升级', '@deepseek-ai/dsh@latest')
  }

  async installNode(): Promise<boolean> {
    const brew = this.tools.brew
    if (!brew) {
      this.setState({ kind: 'failed', label: '未找到 Homebrew', canInstall: false, detail: '未找到 Homebrew' })
      return false
    }
    this.isWorking = true
    this.setState({ kind: 'installing', label: '正在通过 Homebrew 安装 Node.js（可能需要几分钟）…', canInstall: false, detail: '' })
    this.logs.append('environment', 'command', 'brew install node')
    const result = await new Promise<number | null>((done) => {
      const handle = streamCommand(
        brew.path,
        ['install', 'node'],
        {
          onLine: (line, stderr) => this.logs.append('environment', stderr ? 'stderr' : 'stdout', line),
          onExit: (code, error) => {
            if (error) this.logs.append('environment', 'error', error)
            done(code)
          }
        },
        { env: this.spawnEnvironment }
      )
      void handle
    })
    this.isWorking = false
    if (result === 0) {
      this.logs.append('environment', 'success', 'Node.js 安装完成')
      await this.detect()
      return true
    }
    this.setState({ kind: 'failed', label: 'Node.js 安装失败', canInstall: false, detail: 'brew install node 失败，请查看运行日志' })
    return false
  }

  async ensurePnpm(): Promise<boolean> {
    if (this.tools.pnpm) return true
    if (!this.tools.npm) {
      this.logs.append('environment', 'error', '缺少 npm，无法安装 pnpm')
      return false
    }
    this.logs.append('environment', 'info', '未检测到 pnpm，正在准备…')

    const corepack = this.findExecutable('corepack')
    if (corepack) {
      this.logs.append('environment', 'command', 'corepack prepare pnpm@latest --activate')
      const result = await runCommand(corepack, ['prepare', 'pnpm@latest', '--activate'], {
        env: this.spawnEnvironment,
        timeoutMs: 90_000
      })
      if (result.succeeded) {
        const shimDir = join(app.getPath('userData'), 'bin')
        const shimPath = join(shimDir, WINDOWS ? 'pnpm.cmd' : 'pnpm')
        const script = WINDOWS ? `@echo off\r\n"${corepack}" pnpm %*\r\n` : `#!/bin/sh\nexec '${corepack}' pnpm "$@"\n`
        try {
          await fs.mkdir(shimDir, { recursive: true })
          await fs.writeFile(shimPath, script, WINDOWS ? 'utf8' : { encoding: 'utf8', mode: 0o755 })
          const updated = await this.probeTool('pnpm', [shimDir, ...this.tools.knownBinDirectories])
          if (updated) {
            this.tools = { ...this.tools, pnpm: updated, knownBinDirectories: unique([shimDir, ...this.tools.knownBinDirectories]) }
            this.spawnEnvironment = this.buildEnvironment(this.tools.knownBinDirectories)
            this.applySettingsOverrides()
            this.onTools(this.tools)
            this.logs.append('environment', 'success', `pnpm 已通过 Corepack 激活（shim: ${shimPath}）`)
            return true
          }
        } catch (error) {
          this.logs.append('environment', 'warning', `创建 pnpm shim 失败：${String(error)}`)
        }
      }
    }

    const prefix = await this.npmWritablePrefix()
    await fs.mkdir(join(prefix, 'bin'), { recursive: true }).catch(() => undefined)
    this.logs.append('environment', 'command', `npm install --global --prefix ${prefix} pnpm`)
    const result = await new Promise<number | null>((done) => {
      const handle = streamCommand(
        this.tools.npm!.path,
        ['install', '--global', '--prefix', prefix, 'pnpm'],
        {
          onLine: (line, stderr) => this.logs.append('environment', stderr ? 'stderr' : 'stdout', line),
          onExit: (code, error) => {
            if (error) this.logs.append('environment', 'error', error)
            done(code)
          }
        },
        { env: { ...this.spawnEnvironment, npm_config_prefix: prefix } }
      )
      void handle
    })
    if (result === 0) {
      const binDir = join(prefix, 'bin')
      const updated = await this.probeTool('pnpm', [binDir, ...this.tools.knownBinDirectories])
      if (updated) {
        this.tools = { ...this.tools, pnpm: updated, knownBinDirectories: unique([binDir, ...this.tools.knownBinDirectories]) }
        this.spawnEnvironment = this.buildEnvironment(this.tools.knownBinDirectories)
        this.applySettingsOverrides()
        this.onTools(this.tools)
        this.logs.append('environment', 'success', 'pnpm 安装完成')
        return true
      }
    }
    this.logs.append('environment', 'error', 'pnpm 安装失败，请查看日志')
    return false
  }

  // MARK: - 内部实现

  private async installOrUpdateDsh(verb: string, packageSpec: string): Promise<boolean> {
    if (!this.tools.npm) {
      this.setState({ kind: 'failed', label: `缺少 npm，无法${verb} dsh`, canInstall: false, detail: '' })
      return false
    }
    this.isWorking = true
    this.setState({ kind: 'installing', label: `正在${verb} @deepseek-ai/dsh…`, canInstall: false, detail: '' })
    this.logs.append('environment', 'command', `准备${verb} @deepseek-ai/dsh`)

    const prefix = await this.npmWritablePrefix()
    await fs.mkdir(join(prefix, 'bin'), { recursive: true }).catch(() => undefined)
    this.logs.append('environment', 'command', `npm install --global --prefix ${prefix} ${packageSpec}`)

    const result = await new Promise<number | null>((done) => {
      const handle = streamCommand(
        this.tools.npm!.path,
        ['install', '--global', '--prefix', prefix, packageSpec],
        {
          onLine: (line, stderr) => this.logs.append('environment', stderr ? 'stderr' : 'stdout', line),
          onExit: (code, error) => {
            if (error) this.logs.append('environment', 'error', error)
            done(code)
          }
        },
        { env: { ...this.spawnEnvironment, npm_config_prefix: prefix, npm_config_loglevel: 'warn' } }
      )
      void handle
    })

    this.isWorking = false
    if (result === 0) {
      const binDir = join(prefix, 'bin')
      this.tools = { ...this.tools, knownBinDirectories: unique([binDir, ...this.tools.knownBinDirectories]) }
      this.spawnEnvironment = this.buildEnvironment(this.tools.knownBinDirectories)
      this.applySettingsOverrides()
      this.logs.append('environment', 'success', `@deepseek-ai/dsh ${verb}完成`)
      await this.detect()
      return Boolean(this.tools.dsh)
    }
    this.setState({ kind: 'failed', label: `dsh ${verb}失败`, canInstall: false, detail: '请查看运行日志' })
    return false
  }

  private async probe(): Promise<Toolchain> {
    const names = ['node', 'npm', 'dsh', 'pnpm', 'git', 'brew']
    const info: Record<string, ToolInfo | null> = {}

    const custom = this.settings.get().customDshPath.trim()
    if (custom) {
      const path = expandTilde(custom)
      info.dsh = await this.versionOfTool('dsh', path)
    }

    for (const name of names) {
      if (info[name]) continue
      const candidates = executableCandidates(name, this.extraDirectories).slice(0, 12)
      for (const candidate of candidates) {
        const tool = await this.versionOfTool(name, candidate)
        if (tool) {
          info[name] = tool
          break
        }
      }
    }

    const knownBinDirectories = unique([
      ...Object.values(info)
        .filter((tool): tool is ToolInfo => Boolean(tool))
        .map((tool) => dirname(tool.path)),
      ...this.extraDirectories.filter((dir) => existsSync(dir))
    ])

    return {
      dsh: info.dsh ?? null,
      node: info.node ?? null,
      npm: info.npm ?? null,
      pnpm: info.pnpm ?? null,
      git: info.git ?? null,
      brew: info.brew ?? null,
      knownBinDirectories
    }
  }

  private async probeTool(name: string, directories: string[]): Promise<ToolInfo | null> {
    for (const candidate of executableCandidates(name, directories).slice(0, 10)) {
      const tool = await this.versionOfTool(name, candidate)
      if (tool) return tool
    }
    return null
  }

  private async versionOfTool(name: string, executablePath: string): Promise<ToolInfo | null> {
    try {
      await fs.access(executablePath)
      const result = await runCommand(executablePath, ['--version'], {
        env: this.spawnEnvironment,
        timeoutMs: 8000
      })
      const version = result.stdout.trim().split('\n')[0]
      return { name, path: executablePath, version: version || '?' }
    } catch {
      return null
    }
  }

  private findExecutable(name: string): string | null {
    const candidates = executableCandidates(name, this.extraDirectories)
    return candidates.find((path) => existsSync(path)) ?? null
  }

  private buildEnvironment(knownBinDirectories: string[]): NodeJS.ProcessEnv {
    const env = { ...process.env }
    const currentPath = env.PATH ?? (WINDOWS ? '' : '/usr/bin:/bin')
    const entries = currentPath.split(delimiter).filter(Boolean)
    for (const dir of [...knownBinDirectories].reverse()) {
      if (!entries.includes(dir)) entries.unshift(dir)
    }
    env.PATH = entries.join(delimiter)
    return env
  }

  private applySettingsOverrides(): void {
    const settings = this.settings.get()
    const env = { ...this.spawnEnvironment }
    const dshHome = settings.dshHome.trim()
    if (dshHome) env.DSH_HOME = expandTilde(dshHome)
    else delete env.DSH_HOME
    if (settings.telemetryDisabled) env.DSH_TELEMETRY_DISABLED = '1'
    else delete env.DSH_TELEMETRY_DISABLED
    this.spawnEnvironment = env
  }

  private async npmWritablePrefix(): Promise<string> {
    const fallback = WINDOWS
      ? join(homedir(), 'AppData', 'Roaming', 'npm')
      : join(homedir(), '.local')
    if (!this.tools.npm) return fallback
    try {
      const result = await runCommand(this.tools.npm.path, ['config', 'get', 'prefix'], {
        env: this.spawnEnvironment,
        timeoutMs: 10_000
      })
      const prefix = result.stdout.trim().split('\n')[0]
      if (prefix && (await isWritableDir(prefix))) return prefix
    } catch {
      // 使用回退目录。
    }
    return fallback
  }

  private setState(state: EnvironmentState): void {
    this.state = state
    this.onState(state)
  }
}

function expandTilde(path: string): string {
  if (path === '~') return homedir()
  if (path.startsWith('~/') || path.startsWith('~\\')) return join(homedir(), path.slice(2))
  return path
}

function unique(paths: string[]): string[] {
  const seen = new Set<string>()
  const result: string[] = []
  for (const path of paths) {
    const normalized = resolve(path)
    if (!seen.has(normalized)) {
      seen.add(normalized)
      result.push(normalized)
    }
  }
  return result
}

async function isWritableDir(path: string): Promise<boolean> {
  try {
    await fs.access(path, fsConstants.W_OK)
    return true
  } catch {
    return false
  }
}
