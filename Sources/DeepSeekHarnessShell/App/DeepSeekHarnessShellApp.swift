import SwiftUI
import AppKit

@main
struct DeepSeekHarnessShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("DeepSeek Harness Shell", id: "main") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("启动服务") {
                    model.startWeb()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(webRunningDisabled)

                Button("停止服务") {
                    model.stopWeb()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!model.web.isRunning)

                Divider()

                Button("快速跳转…") {
                    model.showCommandPalette = true
                }
                .keyboardShortcut("k", modifiers: [.command])

                Button("插件中心") {
                    model.selection = .plugins
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appInfo) {
                Button("关于 DeepSeek Harness Shell") {
                    model.showAbout = true
                }
            }

            CommandGroup(after: .sidebar) {
                Divider()
                Button("放大") { model.webHost?.zoomIn() }
                    .keyboardShortcut("+", modifiers: [.command])
                    .disabled(model.webHost == nil)
                Button("缩小") { model.webHost?.zoomOut() }
                    .keyboardShortcut("-", modifiers: [.command])
                    .disabled(model.webHost == nil)
                Button("实际大小") { model.webHost?.zoomReset() }
                    .keyboardShortcut("0", modifiers: [.command])
                    .disabled(model.webHost == nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .preferredColorScheme(model.settings.appearance.colorScheme)
                .frame(width: 680, height: 640)
        }

        MenuBarExtra("DeepSeek Harness Shell", systemImage: "terminal.fill") {
            MenuBarContentView()
                .environmentObject(model)
        }
    }

    private var webRunningDisabled: Bool {
        switch model.environment.state {
        case .ready: return false
        default: return model.environment.npmExecutable == nil
        }
    }
}

/// 菜单栏状态组件：服务开关、最近会话与常用入口。
/// 设置「关闭窗口时停止服务」为关时，窗口关闭后应用仍驻留菜单栏。
private struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                BrandMark(size: 28, systemImage: "terminal.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("DeepSeek Harness Shell")
                        .font(.callout.weight(.semibold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            Divider()

            Button {
                if model.web.isRunning {
                    model.stopWeb()
                } else {
                    model.startWeb()
                }
            } label: {
                Label(model.web.isRunning ? "停止服务" : "启动服务",
                      systemImage: model.web.isRunning ? "stop.fill" : "play.fill")
            }
            .disabled(ifStarting)

            Button {
                openMainWindow()
            } label: {
                Label("显示主窗口", systemImage: "macwindow")
            }

            Divider()

            if model.sessionStore.sessions.isEmpty {
                Text("暂无本地会话")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("最近会话")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(model.sessionStore.sessions.prefix(5)) { session in
                    Button {
                        model.openSessionInWeb(session)
                        openMainWindow()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bubble.left.fill")
                                .foregroundStyle(Theme.accent)
                                .font(.caption)
                            Text(session.displayTitle)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if model.isPinned(session) {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                model.selection = .plugins
                openMainWindow()
            } label: {
                Label("插件中心", systemImage: "puzzlepiece.extension")
            }
            Button {
                model.selection = .logs
                openMainWindow()
            } label: {
                Label("运行日志", systemImage: "terminal")
            }
            Button {
                model.selection = .settings
                openMainWindow()
            } label: {
                Label("环境与设置", systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("退出 DeepSeek Harness Shell", systemImage: "power")
            }
        }
        .padding(12)
        .frame(width: 264)
    }

    private var ifStarting: Bool {
        if case .starting = model.web.state { return true }
        return false
    }

    private var statusLabel: String {
        switch model.web.state {
        case .running(let url): return "运行中 · \(url.host ?? "")"
        case .starting: return "正在启动…"
        case .failed: return "服务异常"
        case .stopped: return "未启动"
        }
    }

    private var statusColor: Color {
        switch model.web.state {
        case .running: return .green
        case .starting: return .orange
        case .failed: return .red
        case .stopped: return .secondary
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
