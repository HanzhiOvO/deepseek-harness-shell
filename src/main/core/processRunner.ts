import { spawn, type ChildProcess } from 'node:child_process'
import { createInterface } from 'node:readline'

export interface CommandOptions {
  env?: NodeJS.ProcessEnv
  cwd?: string
  timeoutMs?: number
}

export interface CommandResult {
  code: number | null
  stdout: string
  stderr: string
  timedOut: boolean
  succeeded: boolean
}

export interface StreamHandle {
  child: ChildProcess
  stop(graceMs?: number): void
}

const WINDOWS = process.platform === 'win32'

function quoteCmdArg(value: string): string {
  if (/^[a-zA-Z]:[\\/]/.test(value) || /[\s"&|<>^]/.test(value)) {
    return `"${value.replace(/(\\*)"/g, '$1$1\\"').replace(/(\\+)$/, '$1$1')}"`
  }
  return value
}

function spawnPlatform(command: string, args: string[], options: { env?: NodeJS.ProcessEnv; cwd?: string }): ReturnType<typeof spawn> {
  if (WINDOWS) {
    const commandLine = `${quoteCmdArg(command)} ${args.map(quoteCmdArg).join(' ')}`
    return spawn('cmd.exe', ['/d', '/s', '/c', commandLine], {
      env: options.env ?? process.env,
      cwd: options.cwd,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    })
  }
  return spawn(command, args, {
    env: options.env ?? process.env,
    cwd: options.cwd,
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe']
  })
}

function killTree(child: ReturnType<typeof spawn>): void {
  if (WINDOWS && child.pid) {
    spawn('taskkill', ['/pid', String(child.pid), '/T', '/F'], { windowsHide: true })
    return
  }
  try {
    child.kill('SIGTERM')
  } catch {
    // 已退出。
  }
}

/**
 * 运行短命令并收集输出；非零退出不抛异常，调用方自行判断。
 */
export function runCommand(
  command: string,
  args: string[],
  options: CommandOptions = {}
): Promise<CommandResult> {
  return new Promise((resolve, reject) => {
    const timeoutMs = options.timeoutMs ?? 15_000
    let stdout = ''
    let stderr = ''
    let timedOut = false
    let settled = false

    const child = spawnPlatform(command, args, options)

    const timer = setTimeout(() => {
      timedOut = true
      killTree(child)
    }, timeoutMs)

    child.stdout?.on('data', (chunk: Buffer) => {
      stdout += chunk.toString('utf8')
    })
    child.stderr?.on('data', (chunk: Buffer) => {
      stderr += chunk.toString('utf8')
    })
    child.on('error', (error) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      reject(error)
    })
    child.on('close', (code) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve({
        code,
        stdout,
        stderr,
        timedOut,
        succeeded: code === 0 && !timedOut
      })
    })
  })
}

export interface StreamEvents {
  onLine: (line: string, stderr: boolean) => void
  onExit: (code: number | null, error: string | null) => void
}

/**
 * 流式运行长任务（安装、服务），按行回调。
 * stop() 先 SIGTERM，宽限期后 SIGKILL。
 */
export function streamCommand(
  command: string,
  args: string[],
  events: StreamEvents,
  options: CommandOptions = {}
): StreamHandle {
  const child = spawnPlatform(command, args, options)

  let finished = false
  const finish = (code: number | null, error: string | null): void => {
    if (finished) return
    finished = true
    events.onExit(code, error)
  }

  const consume = (stream: NodeJS.ReadableStream | null, stderr: boolean): void => {
    if (!stream) return
    const reader = createInterface({ input: stream })
    reader.on('line', (line) => events.onLine(line, stderr))
  }
  consume(child.stdout, false)
  consume(child.stderr, true)

  child.on('error', (error) => finish(-1, error.message))
  child.on('close', (code) => finish(code, null))

  return {
    child,
    stop(graceMs = 1800) {
      if (child.exitCode !== null || child.signalCode !== null) return
      killTree(child)
      setTimeout(() => {
        try {
          if (child.exitCode === null && child.signalCode === null) killTree(child)
        } catch {
          // 已经退出。
        }
      }, graceMs)
    }
  }
}
