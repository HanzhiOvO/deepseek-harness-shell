import SwiftUI

@main
struct DeepSeekHarnessShellApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("DeepSeek Harness Shell") {
            RootView()
                .environmentObject(model)
                .environmentObject(model.settings)
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

                Button("插件中心") {
                    model.selection = .plugins
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }

            CommandGroup(after: .appInfo) {
                Button("运行日志") {
                    model.selection = .logs
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.settings)
                .frame(width: 640, height: 600)
        }
    }

    private var webRunningDisabled: Bool {
        switch model.environment.state {
        case .ready: return false
        default: return model.environment.npmExecutable == nil
        }
    }
}
