import SwiftUI

/// 关于面板：版本、架构与资源链接。
struct AboutView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            BrandMark(size: 88, systemImage: "terminal.fill")

            VStack(spacing: 4) {
                Text("DeepSeek Harness Shell")
                    .font(.title.weight(.bold))
                Text("macOS 原生桌面壳 · 版本 \(model.appVersion) (\(buildNumber))")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TintBadge(text: "SwiftUI", systemImage: "swift", color: .orange)
                    TintBadge(text: "WKWebView", systemImage: "safari", color: Theme.accent)
                    TintBadge(text: "零轮询", systemImage: "leaf.fill", color: .green)
                    if let version = model.environment.tools.dsh?.version {
                        TintBadge(text: "dsh \(version)", systemImage: "terminal.fill", color: .purple)
                    }
                }
                .padding(.top, 6)
            }

            VStack(spacing: 4) {
                Text("应用本身不捆绑 Node.js / npm / dsh / Chromium，只负责把官方 DeepSeek Harness 装进原生 Mac 体验：环境配置、插件中心、会话同步、运行日志。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
                Text("数据仍保存在 \(model.plugins.dshHomeDirectory.path)，壳只读同步会话，不迁移、不复制。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            HStack(spacing: 10) {
                Button("官方 dsh 仓库") {
                    open(url: "https://github.com/deepseek-ai/deepseek-harness")
                }
                Button("Node.js 下载") {
                    open(url: "https://nodejs.org/zh-cn/download")
                }
                Button("MIT License") {
                    open(url: "https://opensource.org/license/mit")
                }
            }
            .controlSize(.small)

            Text("© 2025 DeepSeek Harness Shell · 内核为 DeepSeek Harness developer preview")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer(minLength: 8)

            Button("完成") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut(.defaultAction)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(28)
        .frame(width: 560, height: 460)
        .background(Theme.softAccentGradient.opacity(0.45))
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "110"
    }

    private func open(url: String) {
        guard let value = URL(string: url) else { return }
        openURL(value)
    }
}
