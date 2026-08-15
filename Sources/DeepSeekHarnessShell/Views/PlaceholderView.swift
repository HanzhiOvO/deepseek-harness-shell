import SwiftUI
import DeepSeekHarnessCore

struct PlaceholderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.97, blue: 1.0),
                    Color(red: 0.90, green: 0.93, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    appMark
                    content
                    resourceFootnote
                }
                .frame(maxWidth: 560)
                .padding(40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var appMark: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.33, blue: 0.98),
                                     Color(red: 0.10, green: 0.16, blue: 0.52)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 8)

                Image(systemName: "terminal.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Text("DeepSeek Harness Shell")
                .font(.largeTitle.weight(.bold))

            Text("DeepSeek Harness 的原生桌面壳：自动配置环境、管理插件，并把官方 Web UI 装进一个流畅的 Mac 应用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.web.state {
        case .starting:
            StatusCard(
                icon: "hourglass",
                title: "正在启动 Harness…",
                message: "首次启动需要初始化 profile 和依赖，请稍候。"
            )
        case .failed(let message):
            StatusCard(
                icon: "exclamationmark.triangle.fill",
                title: "服务未能运行",
                message: message,
                tint: .red
            ) {
                Button("重试启动") {
                    model.startWeb()
                }
                .buttonStyle(.borderedProminent)
            }
        default:
            environmentContent
        }
    }

    @ViewBuilder
    private var environmentContent: some View {
        switch model.environment.state {
        case .idle, .checking:
            StatusCard(icon: "hourglass", title: "正在检测运行环境…", message: "正在查找 dsh、Node.js、npm、pnpm 等工具链。")
        case .missingDsh(let canInstall, let detail):
            StatusCard(
                icon: "exclamationmark.triangle.fill",
                title: "尚未安装 dsh",
                message: detail,
                tint: .orange
            ) {
                HStack {
                    if canInstall {
                        Button {
                            Task { await model.environment.installDsh() }
                        } label: {
                            Label("一键安装 @deepseek-ai/dsh", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.environment.isWorking)
                    }
                    Button("重新检测") {
                        Task { await model.environment.recheck() }
                    }
                    .disabled(model.environment.isWorking)
                }
            }
        case .missingNode(let canInstall, let detail):
            StatusCard(
                icon: "exclamationmark.triangle.fill",
                title: "缺少 Node.js 运行时",
                message: detail,
                tint: .orange
            ) {
                HStack {
                    if canInstall {
                        Button {
                            Task { await model.environment.installNode() }
                        } label: {
                            Label("通过 Homebrew 安装 Node.js", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.environment.isWorking)
                    }
                    Button("从 nodejs.org 下载") {
                        if let url = URL(string: "https://nodejs.org/zh-cn/download") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("重新检测") {
                        Task { await model.environment.recheck() }
                    }
                    .disabled(model.environment.isWorking)
                }
            }
        case .missingNpm(let detail):
            StatusCard(
                icon: "exclamationmark.triangle.fill",
                title: "检测到 Node.js，但 npm 不可用",
                message: detail,
                tint: .orange
            ) {
                HStack {
                    Button("重新检测") {
                        Task { await model.environment.recheck() }
                    }
                    .disabled(model.environment.isWorking)
                    Button("从 nodejs.org 下载") {
                        if let url = URL(string: "https://nodejs.org/zh-cn/download") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        case .installing(let step):
            StatusCard(icon: "arrow.down.circle.fill", title: step, message: "安装过程会实时写入「运行日志」，完成后将自动重新检测。")
        case .failed(let message):
            StatusCard(icon: "xmark.octagon.fill", title: "环境配置失败", message: message, tint: .red) {
                Button("重新检测") {
                    Task { await model.environment.recheck() }
                }
            }
        case .ready:
            StatusCard(
                icon: "bolt.fill",
                title: "环境已就绪",
                message: "dsh \(model.environment.tools.dsh?.version ?? "可用") · 启动后会自动解析端口并嵌入官方 Web UI。"
            ) {
                Button {
                    model.startWeb()
                } label: {
                    Label("启动 DeepSeek Harness", systemImage: "play.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var resourceFootnote: some View {
        HStack(spacing: 14) {
            Label("无 Electron/Chromium", systemImage: "leaf.fill")
            Label("空闲时无定时器", systemImage: "cpu")
            Label("服务停止即释放内存", systemImage: "memorychip")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
}

struct StatusCard<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = .blue
    @ViewBuilder let actions: () -> Actions

    init(
        icon: String,
        title: String,
        message: String,
        tint: Color = .blue,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.tint = tint
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            actions()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.25))
        )
    }
}

extension StatusCard where Actions == EmptyView {
    init(icon: String, title: String, message: String, tint: Color = .blue) {
        self.init(icon: icon, title: title, message: message, tint: tint) {
            EmptyView()
        }
    }
}
