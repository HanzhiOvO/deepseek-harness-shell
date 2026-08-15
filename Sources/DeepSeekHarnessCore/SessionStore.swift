import Foundation
import Combine
import AppKit

public struct SessionSummary: Identifiable, Equatable, Sendable {
    public let id: String
    public let directoryName: String
    public let workspacePath: String?
    public let title: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let fileURL: URL

    public init(
        id: String,
        directoryName: String,
        workspacePath: String?,
        title: String?,
        createdAt: Date?,
        updatedAt: Date?,
        fileURL: URL
    ) {
        self.id = id
        self.directoryName = directoryName
        self.workspacePath = workspacePath
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.fileURL = fileURL
    }

    public var displayTitle: String {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? directoryName : value
    }

    public var workspaceDisplayName: String {
        guard let workspacePath, !workspacePath.isEmpty else { return "未知工作区" }
        return URL(fileURLWithPath: workspacePath).lastPathComponent
    }
}

/// 本地历史会话同步：
/// - 数据源是 `$DSH_HOME/sessions/<project>/<session>/session.jsonl(.zstd)`，只读不写；
/// - 首次列出目录 + 文件 mtime/size，只有新增/变化才读内容；
/// - 内容读取用 Node 内置 zstd 流式解码，读到标题后立即停止，避免解压整段长会话。
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [SessionSummary] = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncAt: Date?
    @Published public private(set) var lastError: String?

    public let logs = LogStore(limit: 300)

    private struct FileStamp: Equatable {
        let modified: Date
        let size: Int64
    }

    private struct Metadata {
        let headerId: String?
        let workspacePath: String?
        let createdAt: Date?
        let title: String?
    }

    private let environment: EnvironmentManager
    private let settings: AppSettings
    private var stamps: [String: FileStamp] = [:]
    private var metadata: [String: Metadata] = [:]
    private var lastSyncAttempt = Date.distantPast

    public init(environment: EnvironmentManager, settings: AppSettings) {
        self.environment = environment
        self.settings = settings
    }

    public var sessionsRoot: URL {
        let configured = settings.dshHome.trimmingCharacters(in: .whitespaces)
        let base: URL
        if !configured.isEmpty {
            base = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
        } else if let envHome = ProcessInfo.processInfo.environment["DSH_HOME"]?.trimmingCharacters(in: .whitespaces),
                  !envHome.isEmpty {
            base = URL(fileURLWithPath: (envHome as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".dsh", isDirectory: true)
        }
        return base.appendingPathComponent("sessions", isDirectory: true)
    }

    public func sync(force: Bool = false) async {
        let now = Date()
        guard !isSyncing else { return }
        guard force || now.timeIntervalSince(lastSyncAttempt) >= 5 else { return }
        lastSyncAttempt = now
        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        let root = sessionsRoot
        let nodePath = environment.tools.node?.path
        let processEnvironment = environment.spawnEnvironment

        let scanned = await Task.detached(priority: .utility) {
            Self.scanFiles(root: root)
        }.value

        var filesToRead: [ScannedSession] = []
        var currentPaths = Set<String>()
        for item in scanned {
            currentPaths.insert(item.file.path)
            if stamps[item.file.path] != item.stamp {
                filesToRead.append(item)
            }
        }

        // 淘汰已删除的会话缓存。
        for path in stamps.keys where !currentPaths.contains(path) {
            stamps.removeValue(forKey: path)
            metadata.removeValue(forKey: path)
        }

        if !filesToRead.isEmpty {
            logs.append(.info, "发现 \(filesToRead.count) 个新增/变化的本地会话，正在读取元数据…")
        }
        for item in filesToRead.prefix(120) {
            let file = item.file
            let directoryName = item.directoryName
            let read = await Task.detached(priority: .utility) {
                Self.readMetadata(
                    fileURL: file,
                    directoryName: directoryName,
                    nodePath: nodePath,
                    environment: processEnvironment
                )
            }.value
            stamps[file.path] = item.stamp
            metadata[file.path] = read
        }

        var summaries: [SessionSummary] = []
        for item in scanned {
            let info = metadata[item.file.path] ?? Metadata(
                headerId: nil,
                workspacePath: nil,
                createdAt: nil,
                title: nil
            )
            summaries.append(SessionSummary(
                id: info.headerId ?? item.directoryName,
                directoryName: item.directoryName,
                workspacePath: info.workspacePath,
                title: info.title,
                createdAt: info.createdAt,
                updatedAt: item.stamp.modified,
                fileURL: item.file
            ))
        }
        summaries.sort { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        sessions = summaries
        lastSyncAt = now
        logs.append(.success, "历史会话已同步：\(summaries.count) 个（目录 \(root.path)）")
    }

    public func revealInFinder(_ session: SessionSummary) {
        NSWorkspace.shared.activateFileViewerSelecting([session.fileURL])
    }

    // MARK: - 后台实现

    private struct ScannedSession: Sendable {
        let directoryName: String
        let file: URL
        let stamp: FileStamp
    }

    private nonisolated static func scanFiles(root: URL) -> [ScannedSession] {
        let fileManager = FileManager.default
        guard let projectURLs = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [ScannedSession] = []
        for projectURL in projectURLs {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: projectURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let sessionURLs = (try? fileManager.contentsOfDirectory(
                at: projectURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for sessionURL in sessionURLs {
                var sessionIsDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: sessionURL.path, isDirectory: &sessionIsDirectory),
                      sessionIsDirectory.boolValue else { continue }

                let candidates = [
                    sessionURL.appendingPathComponent("session.jsonl.zstd"),
                    sessionURL.appendingPathComponent("session.jsonl")
                ]
                guard let fileURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
                    continue
                }
                let attributes = (try? fileManager.attributesOfItem(atPath: fileURL.path)) ?? [:]
                let modified = attributes[.modificationDate] as? Date ?? .distantPast
                let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                result.append(ScannedSession(
                    directoryName: sessionURL.lastPathComponent,
                    file: fileURL,
                    stamp: FileStamp(modified: modified, size: size)
                ))
            }
        }
        return result.sorted { $0.stamp.modified > $1.stamp.modified }
    }

    private nonisolated static func readMetadata(
        fileURL: URL,
        directoryName: String,
        nodePath: String?,
        environment: [String: String]
    ) -> Metadata {
        guard let nodePath else {
            return Metadata(headerId: nil, workspacePath: nil, createdAt: nil, title: nil)
        }

        let isRaw = fileURL.path.hasSuffix(".jsonl")

        // 首选：zstd CLI 解压 + node 从 stdin 早停读取。
        // dsh 的 .jsonl.zstd 是多帧拼接文件，Node 内置 ZstdDecompress 流不支持第二帧。
        if !isRaw, let zstdPath = findZstdExecutable(environment: environment) {
            let command = "\(shellQuote(zstdPath)) -dc \(shellQuote(fileURL.path)) 2>/dev/null | \(shellQuote(nodePath)) -e \(shellQuote(Self.metadataScriptStdin))"
            if let object = runMetadataCommand(
                executable: "/bin/sh",
                arguments: ["-c", command],
                environment: environment
            ) {
                return object
            }
        }

        // 回退：node 直接读文件。raw 文件可完整早停；zstd 文件至少能读出第一帧头部。
        if let object = runMetadataCommand(
            executable: nodePath,
            arguments: ["-e", Self.metadataScript, fileURL.path],
            environment: environment
        ) {
            return object
        }

        return Metadata(headerId: nil, workspacePath: nil, createdAt: nil, title: directoryName)
    }

    private nonisolated static func runMetadataCommand(
        executable: String,
        arguments: [String],
        environment: [String: String]
    ) -> Metadata? {
        do {
            let result = try ProcessRunner.run(
                executableURL: URL(fileURLWithPath: executable),
                arguments: arguments,
                environment: environment,
                timeout: 30
            )
            guard let line = result.stdout
                .components(separatedBy: "\n")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { !$0.isEmpty }),
                let data = line.data(using: .utf8),
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            let header = object["header"] as? [String: Any]
            let headerId = header?["id"] as? String
            let workspacePath = header?["cwd"] as? String
            let createdAt: Date?
            if let millis = header?["createdAt"] as? Double, millis > 0 {
                createdAt = Date(timeIntervalSince1970: millis / 1000)
            } else if let millis = header?["createdAt"] as? Int, millis > 0 {
                createdAt = Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
            } else {
                createdAt = nil
            }
            let title = (object["title"] as? String) ?? (object["firstUser"] as? String)
            return Metadata(
                headerId: headerId,
                workspacePath: workspacePath,
                createdAt: createdAt,
                title: title
            )
        } catch {
            return nil
        }
    }

    private nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func findZstdExecutable(environment: [String: String]) -> String? {
        let pathDirs = (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init)
        let candidates = (pathDirs + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"])
            .map { ($0 as NSString).appendingPathComponent("zstd") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Node 早停读取脚本：只解压到标题/首个用户消息为止，最多 1500 行。
    private nonisolated static let metadataScript = """
    const fs = require('fs');
    const zlib = require('zlib');
    const readline = require('readline');
    const file = process.argv[1];
    const maxLines = 1500;
    let source = fs.createReadStream(file);
    let dec = null;
    let input = source;
    if (!file.endsWith('.jsonl')) {
      dec = zlib.createZstdDecompress();
      input = source.pipe(dec);
    }
    let header = null;
    let title = null;
    let firstUser = null;
    let lines = 0;
    let done = false;
    let emitted = false;
    function textOf(content) {
      if (!content) return '';
      if (typeof content === 'string') return content;
      if (Array.isArray(content)) return content.map(textOf).join('');
      if (typeof content === 'object') {
        if (typeof content.text === 'string') return content.text;
      }
      return '';
    }
    function stop() {
      if (done) return;
      done = true;
      try { source.destroy(); } catch (e) {}
      try { if (dec) dec.destroy(); } catch (e) {}
      try { rl.close(); } catch (e) {}
    }
    function emit() {
      if (emitted) return;
      emitted = true;
      const out = { header: header, title: title, firstUser: firstUser };
      process.stdout.write(JSON.stringify(out) + '\\n', function () { process.exit(0); });
    }
    const rl = readline.createInterface({ input: input });
    rl.on('line', function (line) {
      if (done) return;
      lines += 1;
      if (lines > maxLines) { stop(); return; }
      let obj = null;
      try { obj = JSON.parse(line); } catch (e) { return; }
      if (!obj || typeof obj !== 'object') return;
      if (!header && obj.type === 'session' && obj.id) {
        header = {
          id: String(obj.id),
          createdAt: typeof obj.createdAt === 'number' ? obj.createdAt : null,
          cwd: typeof obj.cwd === 'string' ? obj.cwd : null
        };
      }
      if (!title && obj.type === 'session/title' && obj.data && typeof obj.data.title === 'string') {
        title = obj.data.title.trim().slice(0, 160);
      }
      if (!firstUser && obj.type === 'user/message' && obj.data) {
        const text = textOf(obj.data.content || (obj.data.message && obj.data.message.content));
        if (text.trim()) firstUser = text.trim().slice(0, 260);
      }
      if (header && title) { stop(); }
    });
    rl.on('error', function () { emit(); });
    rl.on('close', function () { emit(); });
    """

    /// stdin 版本：配合 `zstd -dc` 管道，读到标题后立即退出（SIGPIPE 会同时停掉 zstd）。
    private nonisolated static let metadataScriptStdin = """
    const readline = require('readline');
    const maxLines = 1500;
    let header = null;
    let title = null;
    let firstUser = null;
    let lines = 0;
    let done = false;
    let emitted = false;
    function textOf(content) {
      if (!content) return '';
      if (typeof content === 'string') return content;
      if (Array.isArray(content)) return content.map(textOf).join('');
      if (typeof content === 'object') {
        if (typeof content.text === 'string') return content.text;
      }
      return '';
    }
    function stop() {
      if (done) return;
      done = true;
      try { rl.close(); } catch (e) {}
    }
    function emit() {
      if (emitted) return;
      emitted = true;
      const out = { header: header, title: title, firstUser: firstUser };
      process.stdout.write(JSON.stringify(out) + '\\n', function () { process.exit(0); });
    }
    const rl = readline.createInterface({ input: process.stdin });
    rl.on('line', function (line) {
      if (done) return;
      lines += 1;
      if (lines > maxLines) { stop(); return; }
      let obj = null;
      try { obj = JSON.parse(line); } catch (e) { return; }
      if (!obj || typeof obj !== 'object') return;
      if (!header && obj.type === 'session' && obj.id) {
        header = {
          id: String(obj.id),
          createdAt: typeof obj.createdAt === 'number' ? obj.createdAt : null,
          cwd: typeof obj.cwd === 'string' ? obj.cwd : null
        };
      }
      if (!title && obj.type === 'session/title' && obj.data && typeof obj.data.title === 'string') {
        title = obj.data.title.trim().slice(0, 160);
      }
      if (!firstUser && obj.type === 'user/message' && obj.data) {
        const text = textOf(obj.data.content || (obj.data.message && obj.data.message.content));
        if (text.trim()) firstUser = text.trim().slice(0, 260);
      }
      if (header && title) { stop(); }
    });
    rl.on('error', function () { emit(); });
    rl.on('close', function () { emit(); });
    """
}
