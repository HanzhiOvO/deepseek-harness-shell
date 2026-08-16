import SwiftUI
import AppKit
import DeepSeekHarnessCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL
    @State private var confirmReset = false

    var body: some View {
        ScrollView {
            Form {
                Section("外观") {
                    Picker("主题", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases, id: \.self) { appearance in
                            Label(appearance.label, systemImage: appearance.systemImage)
                                .tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)
                    Text("设置立即生效，并与系统外观保持一致或独立切换。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("DeepSeek Harness 内核") {
                    harnessSection
                }
                Section("启动与运行") {
                    Toggle("启动应用时自动连接 Web UI", isOn: $settings.autoStartWeb)
                    Toggle("检测到缺少 dsh 时自动安装", isOn: $settings.autoInstallDsh)
                    Toggle("关闭窗口时停止服务", isOn: $settings.stopWhenClosed)
                    Toggle("关闭 dsh 遥测", isOn: $settings.telemetryDisabled)

                    LabeledContent("Web 端口（0 = 自动分配）") {
                        TextField("0", value: portBinding, format: .number)
                            .frame(width: 90)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("默认 profile") {
                        TextField("web", text: $settings.profileName)
                            .frame(width: 120)
                            .onSubmit {
                                model.plugins.profileName = settings.profileName
                            }
                    }
                    LabeledContent("DSH_HOME（留空用默认 ~/.dsh）") {
                        TextField("~/.dsh", text: $settings.dshHome)
                            .frame(width: 200)
                            .onSubmit {
                                model.environment.refreshOverrides()
                                model.syncSessions()
                            }
                    }
                }
                Section("DeepSeek API Key") {
                    SecureField("sk-…（可选，也可在 Web UI 内登录）", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Text("仅作为 DEEPSEEK_API_KEY 环境变量传给 dsh 子进程；设置文件保存为 0600 权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("工具链") {
                    toolchainSection
                }
                Section("数据与资源") {
                    HStack(spacing: 8) {
                        Button("打开 DSH 数据目录") {
                            NSWorkspace.shared.open(model.plugins.dshHomeDirectory)
                        }
                        Button("打开插件源码目录") {
                            openPluginSources()
                        }
                        Button("打开应用设置目录") {
                            NSWorkspace.shared.open(settings.settingsURL.deletingLastPathComponent())
                        }
                    }

                    HStack(spacing: 8) {
                        Button("关于 DeepSeek Harness Shell", systemImage: "info.circle") {
                            model.showAbout = true
                        }
                        Button("重置全部设置…", role: .destructive) {
                            confirmReset = true
                        }
                    }

                    Text("DeepSeek Harness Shell \(model.appVersion) · 本应用不捆绑 Node/npm/dsh/Chromium；dsh 与插件保存在系统全局目录，应用本身占用通常小于 10 MB。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.vertical, 8)
        }
        .confirmationDialog("重置全部设置？", isPresented: $confirmReset) {
            Button("恢复默认设置", role: .destructive) {
                settings.resetToDefaults()
                model.plugins.profileName = "web"
                Task { @MainActor in
                    await model.environment.recheck()
                    model.plugins.refreshProfiles()
                    model.syncSessions()
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清除 API Key、端口、profile、DSH_HOME 与收藏等所有偏好。会话与插件数据不会被删除。")
        }
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { settings.webPort },
            set: { settings.webPort = min(max($0, 0), 65535) }
        )
    }

    private func openPluginSources() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = base
            .appendingPathComponent("DeepSeekHarnessShell", isDirectory: true)
            .appendingPathComponent("PluginSources", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    private var harnessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EnvironmentBadge()
                Spacer()
                Button("重新检测") {
                    Task { await model.environment.recheck() }
                }
                .disabled(model.environment.isWorking)
            }

            LabeledContent("自定义 dsh 路径（留空自动探测）") {
                TextField("/usr/local/bin/dsh", text: $settings.customDshPath)
                    .frame(width: 220)
                    .onSubmit {
                        Task { await model.environment.recheck() }
                    }
            }

            HStack(spacing: 8) {
                switch model.environment.state {
                case .missingDsh(let canInstall, _) where canInstall:
                    Button("一键安装 @deepseek-ai/dsh") {
                        Task { await model.environment.installDsh() }
                    }
                    .disabled(model.environment.isWorking)
                case .missingNode(let canInstall, _) where canInstall:
                    Button("通过 Homebrew 安装 Node.js") {
                        Task { await model.environment.installNode() }
                    }
                    .disabled(model.environment.isWorking)
                default:
                    EmptyView()
                }

                if model.environment.tools.dsh != nil, model.environment.tools.npm != nil {
                    Button("升级 dsh 到最新版") {
                        Task { await model.environment.updateDsh() }
                    }
                    .disabled(model.environment.isWorking || model.web.isRunning)
                    .help(model.web.isRunning
                          ? "升级前请先停止 Web 服务，避免覆盖正在运行的 dsh 文件"
                          : "通过 npm 用户级前缀安装 @deepseek-ai/dsh@latest")
                }
            }

            if model.environment.isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.environment.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var toolchainSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.environment.tools.orderedTools, id: \.name) { tool in
                HStack {
                    Text(tool.name)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .frame(width: 44, alignment: .leading)
                    Text(tool.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(tool.version ?? "?")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: tool.path)])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("在 Finder 中显示")
                }
            }
            if model.environment.tools.orderedTools.isEmpty {
                Text("尚未检测工具链")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.environment.tools.pnpm == nil {
                HStack {
                    Label("未找到 pnpm（安装 GitHub/文件夹插件前会自动安装）", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("现在安装 pnpm") {
                        Task { await model.environment.ensurePnpm() }
                    }
                }
            }
        }
    }
}

struct EnvironmentBadge: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.16))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(model.environment.state.label)
                .font(.callout.weight(.medium))
            if let version = model.environment.tools.dsh?.version {
                Text("· dsh \(version)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var color: Color {
        switch model.environment.state {
        case .ready: return .green
        case .checking, .installing, .idle: return .orange
        case .missingDsh, .missingNode, .missingNpm, .failed: return .red
        }
    }
}
