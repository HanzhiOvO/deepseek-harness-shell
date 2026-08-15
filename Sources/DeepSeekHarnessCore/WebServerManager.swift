import Foundation
import Combine

/// 管理 dsh 内嵌 Web 服务进程。
/// 端口 0 表示让 OS 分配空闲端口；从 stdout 解析实际 URL 后交给 WKWebView。
@MainActor
public final class WebServerManager: ObservableObject {
    public enum State: Equatable {
        case stopped
        case starting
        case running(URL)
        case failed(String)

        public var label: String {
            switch self {
            case .stopped: return "未启动"
            case .starting: return "正在启动…"
            case .running(let url): return url.absoluteString
            case .failed(let message): return message
            }
        }
    }

    @Published public private(set) var state: State = .stopped
    public let logs = LogStore(limit: 500)

    private let environment: EnvironmentManager
    private let settings: AppSettings
    private var process: ManagedProcess?
    private var userInitiatedStop = false

    private nonisolated static let urlRegex = try! NSRegularExpression(
        pattern: #"https?://(?:127\.0\.0\.1|localhost|\[::1\]):[0-9]{2,5}"#
    )

    public init(environment: EnvironmentManager, settings: AppSettings) {
        self.environment = environment
        self.settings = settings
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public nonisolated static func urlFromOutput(_ line: String) -> URL? {
        let full = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = urlRegex.firstMatch(in: line, options: [], range: full),
              let range = Range(match.range, in: line) else { return nil }
        return URL(string: String(line[range]))
    }

    public func start() {
        if case .starting = state { return }
        if isRunning { return }

        userInitiatedStop = false
        state = .starting
        logs.clear()
        logs.append(.info, "正在启动 DeepSeek Harness Web UI…")

        // 命令选择：已安装 dsh 时直接调用；只有 npm 时用 npx 临时拉取，不占全局空间。
        let executableURL: URL
        var arguments: [String]
        if let dsh = environment.dshExecutable {
            executableURL = dsh
            arguments = ["web", "--host", "127.0.0.1", "--port", String(settings.sanitizedWebPort())]
        } else if let npm = environment.npmExecutable {
            executableURL = npm
            arguments = [
                "exec", "--yes", "--package=@deepseek-ai/dsh", "--",
                "dsh", "web", "--host", "127.0.0.1", "--port", String(settings.sanitizedWebPort())
            ]
        } else {
            state = .failed("运行环境未就绪：需要 dsh 或 Node.js/npm。请先在「环境与设置」中一键配置。")
            return
        }

        var env = environment.spawnEnvironment
        let dshHome = settings.dshHome.trimmingCharacters(in: .whitespaces)
        if !dshHome.isEmpty {
            env["DSH_HOME"] = (dshHome as NSString).expandingTildeInPath
        }
        let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            env["DEEPSEEK_API_KEY"] = apiKey
        }
        if settings.telemetryDisabled {
            env["DSH_TELEMETRY_DISABLED"] = "1"
        }

        let display = (executableURL.lastPathComponent) + " " + arguments.joined(separator: " ")
        logs.append(.command, display)

        do {
            let managed = try ProcessRunner.stream(
                executableURL: executableURL,
                arguments: arguments,
                environment: env,
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
            ) { [weak self] line, isStderr in
                guard let self else { return }
                self.logs.append(isStderr ? .stderr : .stdout, line)
                if !isStderr, let url = Self.urlFromOutput(line), !self.isRunning {
                    self.state = .running(url)
                    self.logs.append(.success, "Web UI 已就绪：\(url.absoluteString)")
                }
            } onExit: { [weak self] code, error in
                guard let self else { return }
                self.process = nil
                if self.userInitiatedStop {
                    self.state = .stopped
                    return
                }
                let detail = error ?? "进程已退出（exit \(code)）"
                self.state = .failed(detail)
                self.logs.append(.error, "服务停止：\(detail)")
            }
            process = managed
        } catch {
            state = .failed(error.localizedDescription)
            logs.append(.error, error.localizedDescription)
        }
    }

    public func stop() {
        userInitiatedStop = true
        process?.stop(grace: 2.0)
        process = nil
        state = .stopped
        logs.append(.info, "Web 服务已停止")
    }

    public func shutdown() {
        if process != nil {
            stop()
        }
    }
}
