import { promises as fs, existsSync } from 'node:fs'
import { createReadStream } from 'node:fs'
import { readdir, stat } from 'node:fs/promises'
import { basename, dirname, delimiter, join } from 'node:path'
import { homedir } from 'node:os'
import { spawn } from 'node:child_process'
import { createInterface } from 'node:readline'
import type { LogBus } from '../core/logBus'
import type { SettingsService } from './settingsService'
import type { EnvironmentService } from './environmentService'
import type { SessionSummary } from '@shared/types'

interface FileStamp {
  modified: number
  size: number
}

interface SessionMetadata {
  headerId: string | null
  workspacePath: string | null
  createdAt: number | null
  title: string | null
}

interface ScannedSession {
  directoryName: string
  filePath: string
  stamp: FileStamp
}

/** 本地历史会话同步：与 dsh Web UI 读同一份 $DSH_HOME/sessions，只读不写。 */
export class SessionService {
  sessions: SessionSummary[] = []
  isSyncing = false
  lastSyncAt: number | null = null

  private stamps = new Map<string, FileStamp>()
  private metadata = new Map<string, SessionMetadata>()
  private lastSyncAttempt = 0

  constructor(
    private settings: SettingsService,
    private environment: EnvironmentService,
    private logs: LogBus,
    private onSessions: (sessions: SessionSummary[]) => void
  ) {}

  get sessionsRoot(): string {
    const configured = this.settings.get().dshHome.trim()
    if (configured) return join(expandTilde(configured), 'sessions')
    const envHome = (process.env.DSH_HOME ?? '').trim()
    if (envHome) return join(expandTilde(envHome), 'sessions')
    return join(homedir(), '.dsh', 'sessions')
  }

  async sync(force = false): Promise<void> {
    const now = Date.now()
    if (this.isSyncing) return
    if (!force && now - this.lastSyncAttempt < 5000) return
    this.lastSyncAttempt = now
    this.isSyncing = true
    try {
      const root = this.sessionsRoot
      const scanned = await this.scanFiles(root)

      const currentPaths = new Set(scanned.map((item) => item.filePath))
      for (const path of [...this.stamps.keys()]) {
        if (!currentPaths.has(path)) {
          this.stamps.delete(path)
          this.metadata.delete(path)
        }
      }

      const toRead = scanned.filter((item) => {
        const stamp = this.stamps.get(item.filePath)
        return !stamp || stamp.modified !== item.stamp.modified || stamp.size !== item.stamp.size
      })

      if (toRead.length > 0) {
        this.logs.append('sessions', 'info', `发现 ${toRead.length} 个新增/变化的本地会话，正在读取元数据…`)
      }

      for (const item of toRead.slice(0, 120)) {
        this.stamps.set(item.filePath, item.stamp)
        this.metadata.set(item.filePath, await this.readMetadata(item.filePath, item.directoryName))
      }

      const sessions: SessionSummary[] = scanned.map((item) => {
        const info = this.metadata.get(item.filePath)
        const projectName = basename(dirname(item.filePath))
        const directoryName = item.directoryName
        const title = info?.title?.trim() || null
        return {
          id: info?.headerId || directoryName,
          directoryName,
          projectName,
          workspacePath: info?.workspacePath || null,
          title,
          displayTitle: title || directoryName,
          createdAt: info?.createdAt ?? null,
          updatedAt: item.stamp.modified || null,
          filePath: item.filePath
        }
      })
      sessions.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0))
      this.sessions = sessions
      this.lastSyncAt = now
      this.logs.append('sessions', 'success', `历史会话已同步：${sessions.length} 个（目录 ${root}）`)
      this.onSessions(this.sessions)
    } catch (error) {
      this.logs.append('sessions', 'error', `会话同步失败：${String(error)}`)
    } finally {
      this.isSyncing = false
    }
  }

  // MARK: - 后台读取

  private async scanFiles(root: string): Promise<ScannedSession[]> {
    let projectDirs: string[] = []
    try {
      projectDirs = (await readdir(root)).filter((name) => !name.startsWith('.'))
    } catch {
      return []
    }

    const result: ScannedSession[] = []
    for (const project of projectDirs) {
      const projectPath = join(root, project)
      let sessionDirs: string[] = []
      try {
        sessionDirs = (await readdir(projectPath)).filter((name) => !name.startsWith('.'))
      } catch {
        continue
      }
      for (const session of sessionDirs) {
        const sessionPath = join(projectPath, session)
        const candidates = [join(sessionPath, 'session.jsonl.zstd'), join(sessionPath, 'session.jsonl')]
        for (const candidate of candidates) {
          try {
            const fileStat = await stat(candidate)
            if (fileStat.isFile()) {
              result.push({
                directoryName: session,
                filePath: candidate,
                stamp: { modified: fileStat.mtimeMs, size: fileStat.size }
              })
              break
            }
          } catch {
            // 尝试下一个候选。
          }
        }
      }
    }
    return result.sort((a, b) => b.stamp.modified - a.stamp.modified)
  }

  private async readMetadata(filePath: string, fallbackTitle: string): Promise<SessionMetadata> {
    const empty: SessionMetadata = { headerId: null, workspacePath: null, createdAt: null, title: null }
    if (!filePath.endsWith('.jsonl')) {
      const zstd = await this.findZstd()
      if (zstd) {
        const parsed = await this.readViaZstd(zstd, filePath)
        if (parsed) return parsed
      }
      // 无 zstd CLI 时尝试 Electron Node 内置 zstd（单帧/小文件可解析头部）。
      const builtin = await this.readViaBuiltinZstd(filePath)
      if (builtin) return builtin
      return { ...empty, title: fallbackTitle }
    }

    return new Promise((resolvePromise) => {
      let lines = 0
      let header: SessionMetadata['headerId'] = null
      let workspacePath: string | null = null
      let createdAt: number | null = null
      let title: string | null = null
      let firstUser: string | null = null
      let finished = false

      const finish = (): void => {
        if (finished) return
        finished = true
        reader.close()
        source.destroy()
        resolvePromise({
          headerId: header,
          workspacePath,
          createdAt,
          title: title || firstUser || fallbackTitle
        })
      }

      const source = createReadStream(filePath)
      const reader = createInterface({ input: source })
      reader.on('line', (line) => {
        if (finished) return
        lines += 1
        if (lines > 1500) {
          finish()
          return
        }
        const parsed = parseSessionLine(line, { header: header, workspacePath, createdAt, title, firstUser })
        header = parsed.header
        workspacePath = parsed.workspacePath
        createdAt = parsed.createdAt
        title = parsed.title
        firstUser = parsed.firstUser
        if (header && title) finish()
      })
      reader.on('close', finish)
      source.on('error', finish)
    })
  }

  private readViaZstd(zstdPath: string, filePath: string): Promise<SessionMetadata | null> {
    return new Promise((resolvePromise) => {
      const child = spawn(zstdPath, ['-dc', filePath], { stdio: ['ignore', 'pipe', 'ignore'] })
      let lines = 0
      let header: string | null = null
      let workspacePath: string | null = null
      let createdAt: number | null = null
      let title: string | null = null
      let firstUser: string | null = null
      let settled = false

      const settle = (value: SessionMetadata | null): void => {
        if (settled) return
        settled = true
        child.kill('SIGKILL')
        resolvePromise(value)
      }

      const reader = createInterface({ input: child.stdout! })
      reader.on('line', (line) => {
        if (settled) return
        lines += 1
        if (lines > 1500) {
          settle({ headerId: header, workspacePath, createdAt, title: title || firstUser || null })
          return
        }
        const parsed = parseSessionLine(line, { header, workspacePath, createdAt, title, firstUser })
        header = parsed.header
        workspacePath = parsed.workspacePath
        createdAt = parsed.createdAt
        title = parsed.title
        firstUser = parsed.firstUser
        if (header && title) {
          settle({ headerId: header, workspacePath, createdAt, title })
        }
      })
      child.on('error', () => settle(null))
      child.on('close', () => settle({ headerId: header, workspacePath, createdAt, title: title || firstUser || null }))
    })
  }

  private async readViaBuiltinZstd(filePath: string): Promise<SessionMetadata | null> {
    try {
      const zlib = (await import('node:zlib')) as unknown as {
        zstdDecompressSync?: (buffer: Buffer) => Buffer
      }
      if (typeof zlib.zstdDecompressSync !== 'function') return null
      const fileStat = await stat(filePath)
      if (fileStat.size > 160 * 1024 * 1024) return null
      const decompressed = zlib.zstdDecompressSync(await fs.readFile(filePath)).toString('utf8')
      let header: string | null = null
      let workspacePath: string | null = null
      let createdAt: number | null = null
      let title: string | null = null
      let firstUser: string | null = null
      let lines = 0
      for (const line of decompressed.split('\n')) {
        if (lines++ > 1500) break
        const parsed = parseSessionLine(line, { header, workspacePath, createdAt, title, firstUser })
        header = parsed.header
        workspacePath = parsed.workspacePath
        createdAt = parsed.createdAt
        title = parsed.title
        firstUser = parsed.firstUser
        if (header && title) break
      }
      if (!header && !title && !firstUser) return null
      return { headerId: header, workspacePath, createdAt, title: title || firstUser || null }
    } catch {
      return null
    }
  }

  private async findZstd(): Promise<string | null> {
    const pathEntries = (this.environment.spawnEnvironment.PATH ?? '').split(delimiter).filter(Boolean)
    const candidates = [...pathEntries, '/opt/homebrew/bin', '/usr/local/bin', '/usr/bin']
    for (const dir of candidates) {
      const path = join(dir, process.platform === 'win32' ? 'zstd.exe' : 'zstd')
      if (existsSync(path)) return path
    }
    return null
  }
}

interface ParseState {
  header: string | null
  workspacePath: string | null
  createdAt: number | null
  title: string | null
  firstUser: string | null
}

interface ParseResult extends ParseState {}

function parseSessionLine(line: string, previous: ParseState): ParseResult {
  const state = { ...previous }
  let object: Record<string, unknown> | null = null
  try {
    object = JSON.parse(line) as Record<string, unknown>
  } catch {
    return state
  }
  if (!object || typeof object !== 'object') return state

  if (!state.header && object.type === 'session' && object.id) {
    state.header = String(object.id)
    state.createdAt = toTimestamp(object.createdAt)
    if (typeof object.cwd === 'string') state.workspacePath = object.cwd
  }
  if (!state.title && object.type === 'session/title') {
    const data = object.data as Record<string, unknown> | undefined
    if (data && typeof data.title === 'string' && data.title.trim()) {
      state.title = data.title.trim().slice(0, 160)
    }
  }
  if (!state.firstUser && object.type === 'user/message') {
    const data = object.data as Record<string, unknown> | undefined
    if (data) {
      const content = data.content ?? (data.message as Record<string, unknown> | undefined)?.content
      const text = textOf(content).trim()
      if (text) state.firstUser = text.slice(0, 260)
    }
  }
  return state
}

function toTimestamp(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value > 10_000_000_000 ? value : value * 1000
  }
  if (typeof value === 'string') {
    const parsed = Date.parse(value)
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

function textOf(content: unknown): string {
  if (!content) return ''
  if (typeof content === 'string') return content
  if (Array.isArray(content)) return content.map(textOf).join('')
  if (typeof content === 'object') {
    const object = content as Record<string, unknown>
    if (typeof object.text === 'string') return object.text
  }
  return ''
}

function expandTilde(path: string): string {
  if (path === '~') return homedir()
  if (path.startsWith('~/') || path.startsWith('~\\')) return join(homedir(), path.slice(2))
  return path
}
