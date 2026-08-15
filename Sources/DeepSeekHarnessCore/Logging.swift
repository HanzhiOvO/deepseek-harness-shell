import Foundation
import Combine

public enum LogLevel: String, Codable, Sendable {
    case info
    case command
    case stdout
    case stderr
    case warning
    case error
    case success
}

public struct LogEntry: Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let level: LogLevel
    public let text: String

    public init(id: UUID = UUID(), date: Date = Date(), level: LogLevel, text: String) {
        self.id = id
        self.date = date
        self.level = level
        self.text = text
    }
}

/// 环形日志缓冲。进程回调可能来自任意线程，内部统一派发到主线程，
/// 因此 SwiftUI 可以直接观察 `entries` 而不会产生高频刷新。
public final class LogStore: ObservableObject {
    @Published public private(set) var entries: [LogEntry] = []
    public let limit: Int

    public init(limit: Int = 500) {
        self.limit = limit
    }

    public func append(_ level: LogLevel, _ text: String) {
        let entry = LogEntry(level: level, text: text)
        if Thread.isMainThread {
            apply(entry)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.apply(entry)
            }
        }
    }

    private func apply(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
    }

    public func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }

    public var combinedTail: String {
        entries.suffix(30).map(\.text).joined(separator: "\n")
    }
}
