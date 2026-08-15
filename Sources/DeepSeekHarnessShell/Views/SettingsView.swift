import SwiftUI
import DeepSeekHarnessCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            Form {
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
                    }
                    LabeledContent("DSH_HOME（留空用默认 ~/.dsh）") {
                        TextField("~/.dsh", text: $settings.dshHome)
                            .frame(width: 200)
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
                    HStack {
                        Button("打开 DSH 数据目录") {
                            NSWorkspace.shared.open(model.plugins.dshHomeDirectory)
                        }
                        Button("打开应用设置目录") {
                            NSWorkspace.shared.open(settings.settingsURL.deletingLastPathComponent())
                        }
                    }
                    Text("本应用不捆绑 Node/npm/dsh/Chromium；dsh 与插件保存在系统全局目录，应用本身占用通常小于 10 MB。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .padding(.vertical, 8)
        }
    }

    private var portBinding: Binding<Int> {
        Binding(
            get: { settings.webPort },
            set: { settings.webPort = min(max($0, 0), 65535) }
        )
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
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
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
