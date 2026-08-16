import { randomUUID } from 'node:crypto'
import type { LogEntry, LogLevel, LogSource } from '@shared/types'

export type LogListener = (entry: LogEntry) => void

const LIMITS: Record<LogSource, number> = {
  environment: 900,
  web: 700,
  plugins: 900,
  sessions: 400
}

/** 主进程环形日志：按来源保存最近 N 条，并向订阅者广播。 */
export class LogBus {
  private entries = new Map<LogSource, LogEntry[]>()
  private listeners = new Set<LogListener>()

  append(source: LogSource, level: LogLevel, text: string): LogEntry {
    const entry: LogEntry = { id: randomUUID(), date: Date.now(), source, level, text }
    const list = this.entries.get(source) ?? []
    list.push(entry)
    const limit = LIMITS[source]
    while (list.length > limit) list.shift()
    this.entries.set(source, list)
    for (const listener of this.listeners) {
      try {
        listener(entry)
      } catch {
        // 单个订阅者失败不影响其他消费者。
      }
    }
    return entry
  }

  snapshot(): Record<LogSource, LogEntry[]> {
    return {
      environment: [...(this.entries.get('environment') ?? [])].slice(-260),
      web: [...(this.entries.get('web') ?? [])].slice(-260),
      plugins: [...(this.entries.get('plugins') ?? [])].slice(-260),
      sessions: [...(this.entries.get('sessions') ?? [])].slice(-160)
    }
  }

  clear(source?: LogSource): void {
    if (source) {
      this.entries.set(source, [])
    } else {
      this.entries.clear()
    }
  }

  on(listener: LogListener): () => void {
    this.listeners.add(listener)
    return () => this.listeners.delete(listener)
  }
}
