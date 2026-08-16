import { homedir } from 'node:os'
import { streamCommand, type StreamHandle } from '../core/processRunner'
import type { LogBus } from '../core/logBus'
import type { SettingsService } from './settingsService'
import type { EnvironmentService } from './environmentService'
import type { WebServerState } from '@shared/types'
import { parseWebURL } from '@shared/parsers'

/** 管理 dsh web 子进程；端口 0 时解析 stdout 中的实际 URL。 */
export class WebServerService {
  state: WebServerState = { kind: 'stopped' }
  private process: StreamHandle | null = null
  private userInitiatedStop = false

  constructor(
    private environment: EnvironmentService,
    private settings: SettingsService,
    private logs: LogBus,
    private onState: (state: WebServerState) => void
  ) {}

  get isRunning(): boolean {
    return this.state.kind === 'running'
  }

  start(): boolean {
    if (this.state.kind === 'starting' || this.state.kind === 'running') return false
    this.userInitiatedStop = false
    this.setState({ kind: 'starting' })
    this.logs.append('web', 'info', '正在启动 DeepSeek Harness Web UI…')

    const dsh = this.environment.dshExecutable
    const npm = this.environment.npmExecutable
    let command: string
    let args: string[]
    if (dsh) {
      command = dsh
      args = ['web', '--host', '127.0.0.1', '--port', String(this.settings.get().webPort)]
    } else if (npm) {
      command = npm
      args = [
        'exec', '--yes', '--package=@deepseek-ai/dsh', '--',
        'dsh', 'web', '--host', '127.0.0.1', '--port', String(this.settings.get().webPort)
      ]
    } else {
      this.setState({
        kind: 'failed',
        error: '运行环境未就绪：需要 dsh 或 Node.js/npm，请先在「环境与设置」中一键配置。'
      })
      return false
    }

    const env = this.buildEnvironment()
    this.logs.append('web', 'command', `${command} ${args.join(' ')}`)

    this.process = streamCommand(
      command,
      args,
      {
        onLine: (line, stderr) => {
          this.logs.append('web', stderr ? 'stderr' : 'stdout', line)
          if (!stderr && this.state.kind === 'starting') {
            const url = parseWebURL(line)
            if (url) {
              this.setState({ kind: 'running', url: url.toString() })
              this.logs.append('web', 'success', `Web UI 已就绪：${url.toString()}`)
            }
          }
        },
        onExit: (code, error) => {
          this.process = null
          if (this.userInitiatedStop) {
            this.setState({ kind: 'stopped' })
            return
          }
          const detail = error ?? `进程已退出（exit ${code ?? '?'}）`
          this.setState({ kind: 'failed', error: detail })
          this.logs.append('web', 'error', `服务停止：${detail}`)
        }
      },
      { env, cwd: homedir() }
    )
    return true
  }

  stop(): void {
    this.userInitiatedStop = true
    this.process?.stop()
    this.process = null
    this.setState({ kind: 'stopped' })
    this.logs.append('web', 'info', 'Web 服务已停止')
  }

  shutdown(): void {
    this.stop()
  }

  private buildEnvironment(): NodeJS.ProcessEnv {
    const settings = this.settings.get()
    const env = { ...this.environment.spawnEnvironment }
    const dshHome = settings.dshHome.trim()
    if (dshHome) env.DSH_HOME = dshHome.startsWith('~') ? `${homedir()}${dshHome.slice(1)}` : dshHome
    const apiKey = settings.apiKey.trim()
    if (apiKey) env.DEEPSEEK_API_KEY = apiKey
    else delete env.DEEPSEEK_API_KEY
    if (settings.telemetryDisabled) env.DSH_TELEMETRY_DISABLED = '1'
    else delete env.DSH_TELEMETRY_DISABLED
    return env
  }

  private setState(state: WebServerState): void {
    this.state = state
    this.onState(state)
  }
}
