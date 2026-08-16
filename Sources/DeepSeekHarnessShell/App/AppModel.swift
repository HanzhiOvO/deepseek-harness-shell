import SwiftUI
import Combine
import DeepSeekHarnessCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case chat
    case history
    case plugins
    case logs
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "对话"
        case .history: return "历史会话"
        case .plugins: return "插件中心"
        case .logs: return "运行日志"
        case .settings: return "环境与设置"
        }
    }

    var systemImage: String {
        switch self {
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .history: return "clock.arrow.circlepath"
        case .plugins: return "puzzlepiece.extension.fill"
        case .logs: return "terminal.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

enum InstallKind: String, CaseIterable, Identifiable {
    case github
    case zip
    case folder
    case npm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .github: return "GitHub 仓库"
        case .zip: return "ZIP 压缩包"
        case .folder: return "本地文件夹"
        case .npm: return "npm 包"
        }
    }

    var systemImage: String {
        switch self {
        case .github: return "link"
        case .zip: return "doc.zipper"
        case .folder: return "folder.badge.plus"
        case .npm: return "shippingbox"
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    static weak var shared: AppModel?

    let settings: AppSettings
    let environment: EnvironmentManager
    let plugins: PluginManager
    let web: WebServerManager
    let sessionStore: SessionStore

    @Published var selection: SidebarItem = .chat
    @Published var selectedSession: SessionSummary?
    @Published var webHost: WebHost?
    @Published var installSheet: InstallKind?
    @Published var installPreloadedURL: URL?
    @Published var showCommandPalette = false
    @Published var showAbout = false
    private var pendingSession: SessionSummary?

    private var cancellables = Set<AnyCancellable>()
    private var didBootstrap = false

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.environment = EnvironmentManager(settings: settings)
        self.plugins = PluginManager(environment: environment, settings: settings)
        self.web = WebServerManager(environment: environment, settings: settings)
        self.sessionStore = SessionStore(environment: environment, settings: settings)
        Self.shared = self

        web.$state
            .sink { [weak self] state in
                self?.syncWebHost(state)
                if case .running = state {
                    Task { @MainActor in
                        await self?.sessionStore.sync()
                    }
                }
            }
            .store(in: &cancellables)
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true

        Task { @MainActor in
            await environment.detect()
            plugins.refreshProfiles()

            if case .missingDsh(let canInstall, _) = environment.state,
               settings.autoInstallDsh,
               canInstall {
                if await environment.installDsh() {
                    plugins.refreshProfiles()
                }
            }

            if case .ready = environment.state, settings.autoStartWeb {
                web.start()
            }
            // Web 进程已异步启动，随后同步本地历史会话（内部有变更缓存与节流）。
            await sessionStore.sync(force: true)
        }
    }

    func startWeb() {
        switch environment.state {
        case .ready:
            web.start()
        case .idle, .checking:
            break
        default:
            if environment.npmExecutable != nil {
                web.start()
            } else {
                selection = .settings
            }
        }
    }

    func stopWeb() {
        web.stop()
        webHost = nil
        pendingSession = nil
    }

    func showSession(_ session: SessionSummary) {
        selectedSession = session
        selection = .history
    }

    /// 打开插件安装面板；可选预填一个拖入的文件/文件夹。
    func openInstallSheet(_ kind: InstallKind, preloadedURL: URL? = nil) {
        installPreloadedURL = preloadedURL
        installSheet = kind
    }

    /// 在官方 Web UI 中打开本地历史会话：先确保服务/页面就绪，
    /// 再通过 WebHost 的会话选择脚本恢复该会话。
    func openSessionInWeb(_ session: SessionSummary) {
        selectedSession = session
        selection = .chat

        switch web.state {
        case .running:
            if let host = webHost {
                host.openSession(id: session.id, title: session.displayTitle)
            } else {
                pendingSession = session
                web.start()
            }
        case .starting:
            pendingSession = session
        case .stopped, .failed:
            pendingSession = session
            web.start()
        }
    }

    func syncSessions() {
        Task { @MainActor in
            await sessionStore.sync(force: true)
        }
    }

    func isPinned(_ session: SessionSummary) -> Bool {
        settings.isPinned(session.id)
    }

    func togglePin(_ session: SessionSummary) {
        settings.togglePin(session.id)
    }

    func shutdown() {
        web.shutdown()
    }

    // MARK: - 展示信息

    var runningURL: URL? {
        if case .running(let url) = web.state { return url }
        return nil
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
    }

    private func syncWebHost(_ state: WebServerManager.State) {
        switch state {
        case .running(let url):
            if webHost == nil {
                let host = WebHost()
                webHost = host
                host.load(url)
            }
            if let session = pendingSession, let host = webHost {
                pendingSession = nil
                host.openSession(id: session.id, title: session.displayTitle)
            }
        case .stopped:
            webHost = nil
            pendingSession = nil
        case .failed:
            webHost = nil
            pendingSession = nil
        case .starting:
            break
        }
    }
}
