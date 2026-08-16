import DeepSeekHarnessCore
import Foundation
import Darwin

@main
struct SmokeMain {
    @MainActor
    static func main() async {
        let settings = AppSettings()
        let environment = EnvironmentManager(settings: settings)

        print("== 检测环境 ==")
        await environment.detect()
        print("状态: \(environment.state.label)")
        for tool in environment.tools.orderedTools {
            print("  \(tool.name): \(tool.version ?? "?") @ \(tool.path)")
        }

        guard environment.dshExecutable != nil else {
            print("SMOKE FAIL: dsh 不可用")
            exit(1)
        }

        print("== 插件清单（应包含 dsh 随附 bundle）==")
        let pluginManager = PluginManager(environment: environment, settings: settings)
        pluginManager.refreshProfiles()
        print("插件数: \(pluginManager.installed.count)")
        for plugin in pluginManager.installed.prefix(6) {
            print("  - \(plugin.name) v\(plugin.version ?? "?") inbox=\(plugin.isInbox) bundle=\(plugin.isBundle)")
        }
        guard pluginManager.installed.contains(where: { $0.name == "@deepseek-ai/dsh-base" && $0.isInbox }) else {
            print("SMOKE FAIL: 未显示 dsh 随附内置 bundle")
            exit(1)
        }

        print("== 同步本地历史会话 ==")
        let sessionStore = SessionStore(environment: environment, settings: settings)
        await sessionStore.sync(force: true)
        print("会话数: \(sessionStore.sessions.count)")
        for session in sessionStore.sessions.prefix(3) {
            print("  - [\(session.workspaceDisplayName)] \(session.displayTitle)")
            print("    id=\(session.id) updated=\(session.updatedAt?.formatted() ?? "?")")
        }

        print("== 启动 dsh web（端口 0）==")
        let web = WebServerManager(environment: environment, settings: settings)
        web.start()

        var servedURL: URL?
        for _ in 0..<120 {
            if case .running(let url) = web.state {
                servedURL = url
                break
            }
            if case .failed(let message) = web.state {
                print("SMOKE FAIL: \(message)")
                exit(1)
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        guard let url = servedURL else {
            print("SMOKE FAIL: 30 秒内未解析出服务 URL")
            web.stop()
            exit(1)
        }

        print("服务 URL: \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("HTTP \(status), \(data.count) bytes")
            guard status == 200, data.count > 100 else {
                print("SMOKE FAIL: 首页响应异常")
                web.stop()
                exit(1)
            }
        } catch {
            print("SMOKE FAIL: \(error.localizedDescription)")
            web.stop()
            exit(1)
        }

        print("== 停止服务 ==")
        web.stop()
        print("SMOKE PASS")
        exit(0)
    }
}
