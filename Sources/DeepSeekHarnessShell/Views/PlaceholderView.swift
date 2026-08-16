import SwiftUI
import DeepSeekHarnessCore

struct PlaceholderView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(spacing: 26) {
                    appMark
                    content
                    shortcutHints
                    resourceFootnote
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 背景

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.97, green: 0.98, blue: 1.0),
                    Color(red: 0.88, green: 0.93, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Theme.accent.opacity(0.10))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: -280, y: -250)

            Circle()
                .fill(Color.indigo.opacity(0.08))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .offset(x: 300, y: 260)
        }
    }

    // MARK: - 品牌

    private var appMark: some View {
        VStack(spacing: 12) {
            BrandMark(size: 92, systemImage: "terminal.fill")

            Text("DeepSeek Harness Shell")
                .font(.largeTitle.weight(.bold))

            Text("DeepSeek Harness 的原生桌面壳：自动配置环境、管理插件，并把官方 Web UI 装进一个流畅的 Mac 应用。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TintBadge(text: "v\(model.appVersion) · macOS 13+", systemImage: "checkmark.seal.fill", color: Theme.accent)
        }
    }

    // MARK: - 状态内容

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
                HStack {
                    Button("重试启动") {
                        model.startWeb()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("查看日志") {
                        model.selection = .logs
                    }
                }
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
            VStack(spacing: 14) {
                StatusCard(
                    icon: "bolt.fill",
                    title: "环境已就绪",
                    message: "dsh \(model.environment.tools.dsh?.version ?? "可用") · 启动后会自动解析端口并嵌入官方 Web UI。",
                    tint: Theme.success
                ) {
                    Button {
                        model.startWeb()
                    } label: {
                        Label("启动 DeepSeek Harness", systemImage: "play.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accent)
                }

                if !model.sessionStore.sessions.isEmpty {
                    RecentSessionsPanel(sessions: model.sessionStore.sessions.prefix(3).map { $0 }) {
                        model.openSessionInWeb($0)
                    }
                }
            }
        }
    }

    // MARK: - 底部提示

    private var shortcutHints: some View {
        HStack(spacing: 10) {
            ShortcutChip(keys: "⌘R", label: "启动服务")
            ShortcutChip(keys: "⌘.", label: "停止服务")
            ShortcutChip(keys: "⌘K", label: "快速跳转")
            ShortcutChip(keys: "⌘⇧P", label: "插件中心")
        }
    }

    private var resourceFootnote: some View {
        VStack(spacing: 8) {
            HStack(spacing: 14) {
                Label("无 Electron/Chromium", systemImage: "leaf.fill")
                Label("空闲时无定时器", systemImage: "cpu")
                Label("服务停止即释放内存", systemImage: "memorychip")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text("按 ⌘K 可随时搜索会话或跳转功能")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }
}

private struct ShortcutChip: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecentSessionsPanel: View {
    let sessions: [SessionSummary]
    let onOpen: (SessionSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("继续最近会话", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            ForEach(sessions) { session in
                Button {
                    onOpen(session)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.text.bubble.right.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.displayTitle)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            Text("\(session.projectName) · \(session.workspaceDisplayName) · \(session.updatedAt?.formatted(.relative(presentation: .named)) ?? "未知时间")")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Theme.cardStroke)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusCard<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Theme.accent
    @ViewBuilder let actions: () -> Actions

    init(
        icon: String,
        title: String,
        message: String,
        tint: Color = Theme.accent,
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
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }
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
        .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
    }
}

extension StatusCard where Actions == EmptyView {
    init(icon: String, title: String, message: String, tint: Color = Theme.accent) {
        self.init(icon: icon, title: title, message: message, tint: tint) {
            EmptyView()
        }
    }
}
